defmodule NervesHubWeb.Live.Account.TwoFactor do
  @moduledoc """
  Where a user turns two-factor authentication on or off, and makes new
  recovery codes. Members an organization turns away for not having it are
  sent here. See `NervesHub.Accounts.TwoFactor`.

  Setting it up keeps the new secret in this process until a code from the
  app confirms it; nothing is stored before then.
  """
  use NervesHubWeb, :live_view

  alias NervesHub.Accounts
  alias NervesHub.Accounts.TwoFactor
  alias NervesHub.Accounts.User
  alias NervesHubWeb.Plugs.Attack

  @impl Phoenix.LiveView
  @decorate requires_no_permission()
  def mount(_params, session, socket) do
    socket
    |> page_title("Two-factor authentication")
    # The session this page is open in, which stays signed in when turning
    # two-factor on signs the others out.
    |> assign(:session_token, session["user_token"])
    |> assign(:setup_secret, nil)
    |> assign(:recovery_codes, nil)
    |> assign(:error, nil)
    |> load()
    |> ok()
  end

  defp load(%{assigns: %{current_scope: %{user: user}}} = socket) do
    socket
    |> assign(:available?, TwoFactor.available?())
    |> assign(:totp, TwoFactor.get(user))
    |> assign(:orgs_requiring, TwoFactor.orgs_requiring(user))
  end

  @impl Phoenix.LiveView
  @decorate requires_no_permission()
  def handle_event("start-setup", _params, socket) do
    socket
    |> assign(:setup_secret, TwoFactor.new_secret())
    |> assign(:error, nil)
    |> noreply()
  end

  @decorate requires_no_permission()
  def handle_event("cancel-setup", _params, socket) do
    socket
    |> assign(:setup_secret, nil)
    |> assign(:error, nil)
    |> noreply()
  end

  @decorate requires_no_permission()
  def handle_event("enable", params, %{assigns: %{setup_secret: secret}} = socket) when is_binary(secret) do
    user = socket.assigns.current_scope.user

    # Turning it on shuts out anyone without the app, so a signed in browser
    # alone isn't enough: the password is asked for too, from accounts that
    # have one.
    with :ok <- check_attempts(user),
         :ok <- check_password(user, params["password"]),
         {:ok, codes} <- TwoFactor.enable(user, secret, params["code"] || "") do
      # Whoever holds another of the user's sessions never typed a code, and
      # may be someone who got in with a stolen password before now.
      :ok = Accounts.delete_other_user_session_tokens(user, socket.assigns.session_token)

      socket
      |> assign(:setup_secret, nil)
      |> assign(:recovery_codes, codes)
      |> assign(:error, nil)
      |> load()
      |> put_flash(:info, "Two-factor authentication is on. Your other browser sessions were signed out.")
      |> noreply()
    else
      {:error, reason} -> socket |> assign(:error, error_message(reason)) |> noreply()
    end
  end

  @decorate requires_no_permission()
  def handle_event("enable", _params, socket), do: noreply(socket)

  @decorate requires_no_permission()
  def handle_event("regenerate", %{"code" => code}, socket) do
    user = socket.assigns.current_scope.user

    with :ok <- check_attempts(user),
         {:ok, codes} <- TwoFactor.regenerate_recovery_codes(user, code) do
      socket
      |> assign(:recovery_codes, codes)
      |> assign(:error, nil)
      |> load()
      |> put_flash(:info, "New recovery codes made. The old ones no longer work.")
      |> noreply()
    else
      {:error, reason} -> socket |> assign(:error, error_message(reason)) |> noreply()
    end
  end

  @decorate requires_no_permission()
  def handle_event("disable", %{"code" => code}, socket) do
    user = socket.assigns.current_scope.user

    with :ok <- check_attempts(user),
         :ok <- TwoFactor.disable(user, code) do
      socket
      |> assign(:recovery_codes, nil)
      |> assign(:error, nil)
      |> load()
      |> put_flash(:info, "Two-factor authentication is off.")
      |> noreply()
    else
      {:error, reason} -> socket |> assign(:error, error_message(reason)) |> noreply()
    end
  end

  @decorate requires_no_permission()
  def handle_event("hide-recovery-codes", _params, socket) do
    socket |> assign(:recovery_codes, nil) |> noreply()
  end

  # A code, or the password, is what stops a signed in browser alone from
  # changing any of this, so how often one can be tried is limited.
  defp check_attempts(%User{id: user_id}) do
    case Attack.two_factor_change_throttle(user_id) do
      {:allow, _data} -> :ok
      {:block, _data} -> {:error, :too_many_attempts}
    end
  end

  # Accounts that only sign in with Google have no password to ask for.
  defp check_password(%User{password_hash: nil}, _password), do: :ok

  defp check_password(%User{} = user, password) do
    if User.valid_password?(user, password), do: :ok, else: {:error, :invalid_password}
  end

  defp error_message(:invalid_password), do: "That password isn't right."
  defp error_message(:invalid_code), do: "That code didn't work. Check your authenticator app and try again."

  defp error_message(:too_many_attempts),
    do: "Too many tries. To keep your account safe, wait ten minutes, then try again."

  defp error_message(:secret_unreadable),
    do: "Codes from your authenticator app can't be checked on this server right now. Use a recovery code instead."

  defp error_message(:already_enabled), do: "Two-factor authentication is already on."
  defp error_message(:unavailable), do: "Two-factor authentication isn't available on this server."

  defp qr_code(uri) do
    uri
    |> EQRCode.encode()
    |> EQRCode.svg(width: 192, background_color: "#ffffff", color: "#000000", viewbox: true)
    |> Phoenix.HTML.raw()
  end

  defp recovery_codes_file(codes) do
    body =
      [
        "#{NervesHub.Branding.friendly_platform_name()} recovery codes",
        "Each code signs you in once, without your authenticator app.",
        "" | codes
      ]
      |> Enum.join("\n")

    # As a tuple, since `link/1` refuses a `data:` URL given as a string.
    {:data, "text/plain;charset=utf-8," <> URI.encode(body, &URI.char_unreserved?/1)}
  end

  defp org_names(orgs), do: orgs |> Enum.map(& &1.name) |> join_names()

  defp join_names([name]), do: name

  defp join_names(names) do
    {rest, [last]} = Enum.split(names, -1)
    Enum.join(rest, ", ") <> " and " <> last
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <NervesHubWeb.Layouts.no_sidebar flash={@flash} current_scope={@current_scope}>
      <div class="w-full max-w-[800px] pb-10">
        <div class="flex h-[88px] items-center justify-between py-6">
          <h1 class="text-page-title text-content-strong">Two-factor authentication</h1>
          <.button type="link" navigate={~p"/account"}>Back to account</.button>
        </div>

        <div class="flex flex-col gap-6">
          <div :if={@orgs_requiring != [] && is_nil(@totp)} id="two-factor-required" role="alert" class="flex gap-2.5 rounded-card border border-warning/30 bg-warning-soft p-4 text-sm text-content-body">
            <span class="mt-0.5 lucide-shield-exclamation-point size-4 flex-none text-warning" aria-hidden="true"></span>
            <p>
              {org_names(@orgs_requiring)} {if length(@orgs_requiring) == 1, do: "requires", else: "require"} two-factor authentication. Turn it on to reach {if length(@orgs_requiring) == 1,
                do: "it",
                else: "them"}.
            </p>
          </div>

          <div :if={@recovery_codes} id="recovery-codes" class="rounded-card border border-primary bg-surface-raised p-4 shadow-card">
            <h2 class="mb-2 text-section-title text-content-strong">Save your recovery codes</h2>
            <p class="mb-4 text-sm text-content-muted">
              Each code signs you in once if you lose your phone. Keep them somewhere safe, like a password manager. They won't be shown again.
            </p>
            <ul class="mb-4 grid grid-cols-2 gap-2 rounded-card border border-line-default bg-surface p-4 font-mono text-sm text-content-strong sm:grid-cols-5">
              <li :for={code <- @recovery_codes}>{code}</li>
            </ul>
            <div class="flex flex-wrap gap-2">
              <.button
                id="copy-recovery-codes"
                type="button"
                phx-hook="CopyToClipboard"
                data-copy-value={Enum.join(@recovery_codes, "\n")}
              >
                <span data-icon="copy" class="lucide-copy size-4"></span>
                <span data-icon="check" class="lucide-check hidden size-4 text-success"></span> Copy
              </.button>
              <.button type="link" href={recovery_codes_file(@recovery_codes)} download="recovery-codes.txt">
                <span class="lucide-download size-4"></span> Download
              </.button>
              <.button type="button" style="primary" phx-click="hide-recovery-codes">I've saved them</.button>
            </div>
          </div>

          <div :if={!@available?} id="two-factor-unavailable" class="rounded-card border border-line-default bg-surface-raised p-4 shadow-card">
            <h2 class="mb-2 text-section-title text-content-strong">Not available</h2>
            <p class="text-sm text-content-muted">
              Two-factor authentication needs this server to have a key for encrypting secrets. Ask your platform admin to set <span class="font-mono">SECRETS_ENCRYPTION_KEY</span>.
            </p>
          </div>

          <div :if={@available? && is_nil(@totp) && is_nil(@setup_secret)} id="two-factor-off" class="rounded-card border border-line-default bg-surface-raised p-4 shadow-card">
            <h2 class="mb-2 text-section-title text-content-strong">Off</h2>
            <p class="mb-4 text-sm text-content-muted">
              With two-factor authentication on, signing in asks for a code from an authenticator app on your phone, such as 1Password, Google Authenticator or Authy, as well as your password. Someone who learns your password still can't sign in.
            </p>
            <.button id="start-setup" style="primary" type="button" phx-click="start-setup">
              <span class="lucide-shield-check size-4"></span> Set up two-factor authentication
            </.button>
          </div>

          <div :if={@setup_secret} id="two-factor-setup" class="rounded-card border border-line-default bg-surface-raised p-4 shadow-card">
            <h2 class="mb-4 text-section-title text-content-strong">Set up your authenticator app</h2>
            <div class="flex flex-col gap-6 md:flex-row">
              <div class="flex shrink-0 flex-col items-center gap-2">
                <div id="two-factor-qr-code" class="size-48 rounded-md bg-white p-2">
                  {qr_code(TwoFactor.otpauth_uri(@current_scope.user, @setup_secret))}
                </div>
              </div>

              <div class="flex min-w-0 flex-1 flex-col gap-4">
                <ol class="list-decimal space-y-2 pl-5 text-sm text-content-body">
                  <li>Scan the QR code with your authenticator app.</li>
                  <li>
                    Can't scan it? Add a time-based key by hand instead:
                    <span id="two-factor-secret" class="mt-1 block font-mono break-all text-content-strong">{TwoFactor.format_secret(@setup_secret)}</span>
                  </li>
                  <li>Type in the six digit code the app shows.</li>
                </ol>

                <.form for={%{}} id="two-factor-enable-form" phx-submit="enable" class="flex flex-col gap-4">
                  <div class="max-w-sm">
                    <NervesHubWeb.CoreComponents.label for="setup_code">Code from the app</NervesHubWeb.CoreComponents.label>
                    <NervesHubWeb.Components.OtpInput.otp_input id="setup_code" name="code" invalid={!is_nil(@error)} hook required />
                  </div>
                  <.input :if={@current_scope.user.password_hash} id="setup_password" name="password" type="password" value="" label="Your password" autocomplete="current-password" required />
                  <p :if={@error} id="two-factor-error" role="alert" class="text-sm text-alert-content">{@error}</p>
                  <div class="flex gap-2">
                    <.button style="primary" type="submit">Turn on</.button>
                    <.button type="button" phx-click="cancel-setup">Cancel</.button>
                  </div>
                </.form>
              </div>
            </div>
          </div>

          <div :if={@totp} id="two-factor-on" class="rounded-card border border-line-default bg-surface-raised p-4 shadow-card">
            <div class="mb-2 flex items-center gap-2">
              <h2 class="text-section-title text-content-strong">On</h2>
              <.badge tone="success">Enabled</.badge>
            </div>
            <p class="text-sm text-content-muted">
              Turned on <.local_datetime at={@totp.inserted_at} time_zone={@time_zone} format={:long_date} zone_label={false} />.
              You have {length(@totp.recovery_codes)} recovery {if length(@totp.recovery_codes) == 1, do: "code", else: "codes"} left.
            </p>
            <p :if={@error} id="two-factor-error" role="alert" class="mt-4 text-sm text-alert-content">{@error}</p>

            <div class="mt-6 flex flex-col gap-6 border-t border-line-default pt-6">
              <.form for={%{}} id="two-factor-regenerate-form" phx-submit="regenerate" class="flex flex-col gap-3">
                <div>
                  <h3 class="text-group-title text-content-strong">New recovery codes</h3>
                  <p class="text-sm text-content-muted">Makes ten new codes. The ones you have stop working.</p>
                </div>
                <div class="flex flex-col gap-3 sm:flex-row sm:items-end">
                  <.input id="regenerate_code" name="code" value="" label="Code from the app, or a recovery code" autocomplete="one-time-code" required />
                  <.button type="submit">Make new codes</.button>
                </div>
              </.form>

              <.form for={%{}} id="two-factor-disable-form" phx-submit="disable" class="flex flex-col gap-3">
                <div>
                  <h3 class="text-group-title text-content-strong">Turn off two-factor authentication</h3>
                  <p class="text-sm text-content-muted">Signing in will only ask for your password.</p>
                  <p :if={@orgs_requiring != []} id="two-factor-disable-warning" class="mt-1 text-sm text-warning-content">
                    {org_names(@orgs_requiring)} {if length(@orgs_requiring) == 1, do: "requires", else: "require"} it, so you won't be able to reach {if length(@orgs_requiring) == 1,
                      do: "it",
                      else: "them"} until you turn it back on.
                  </p>
                </div>
                <div class="flex flex-col gap-3 sm:flex-row sm:items-end">
                  <.input id="disable_code" name="code" value="" label="Code from the app, or a recovery code" autocomplete="one-time-code" required />
                  <.button style="danger" type="submit">Turn off</.button>
                </div>
              </.form>
            </div>
          </div>
        </div>
      </div>
    </NervesHubWeb.Layouts.no_sidebar>
    """
  end
end

defmodule NervesHubWeb.Live.AccountMFA do
  @moduledoc """
  LiveView for managing Multi-Factor Authentication (MFA) settings in user accounts.
  """

  use NervesHubWeb, :updated_live_view

  alias NervesHub.Accounts
  alias NervesHub.Accounts.MFA

  embed_templates("account_mfa_templates/*")

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    socket
    |> apply_action(socket.assigns.live_action, params)
    |> noreply()
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> page_title("Account Multi-Factor Authentication")
    |> assign_current_totp()
    |> render_with(&account_mfa_form_template/1)
  end

  @impl Phoenix.LiveView
  def handle_event("toggle-mfa", _params, socket) do
    user = Accounts.get_user!(socket.assigns.user.id)
    user_totp = MFA.get_user_totp(user)
    socket = if user_totp, do: delete_user_totp(socket, user_totp), else: assign_totp_qr(socket)
    {:noreply, socket}
  end

  def handle_event("confirm-mfa-totp", %{"user_totp" => %{"code" => code}}, socket) do
    totp = socket.assigns.editing_totp

    socket =
      case MFA.upsert_user_totp(totp, %{code: code}) do
        {:ok, current_totp} ->
          socket
          |> reset_totp_assigns(current_totp)
          |> assign(:backup_codes, current_totp.backup_codes)

        {:error, changeset} ->
          socket
          |> assign(:totp_form, to_form(changeset))
      end

    {:noreply, socket}
  end

  def handle_event("toggle-backup-codes", %{}, socket) do
    backup_codes_visible = !socket.assigns.backup_codes_visible
    {:noreply, assign(socket, :backup_codes_visible, backup_codes_visible)}
  end

  def handle_event("regenerate-backup-codes", _params, socket) do
    user = Accounts.get_user!(socket.assigns.user.id)
    user_totp = MFA.get_user_totp(user)

    socket =
      case MFA.regenerate_user_totp_backup_codes(user_totp) do
        {:ok, totp} ->
          socket
          |> put_flash(:info, "Backup codes regenerated successfully.")
          |> assign_current_totp(totp)
          |> assign(:backup_codes_visible, true)

        {:error, changeset} ->
          socket
          |> put_flash(:error, "Failed to regenerate backup codes.")
          |> assign(:totp_form, to_form(changeset))
      end

    {:noreply, socket}
  end

  defp delete_user_totp(socket, user_totp) do
    case MFA.delete_user_totp(user_totp) do
      {:ok, _} ->
        socket
        |> put_flash(:info, "Multi-Factor Authentication disabled successfully.")
        |> assign_current_totp(nil)

      {:error, _changeset} ->
        socket
        |> put_flash(:error, "Failed to disable Multi-Factor Authentication.")
    end
  end

  defp assign_current_totp(socket, totp \\ nil) do
    socket
    |> assign(:current_totp, totp || MFA.get_user_totp(socket.assigns.user))
    |> assign(:backup_codes_visible, false)
  end

  defp assign_totp_qr(socket) do
    user = socket.assigns.user
    editing_totp = %MFA.UserTOTP{user_id: user.id}
    app = "NervesHub"
    secret = NimbleTOTP.secret()
    qrcode_uri = NimbleTOTP.otpauth_uri("#{app}:#{user.email}", secret, issuer: app)

    editing_totp = %{editing_totp | secret: secret}

    socket
    |> assign(:editing_totp, editing_totp)
    |> assign(:qrcode_uri, qrcode_uri)
    |> assign(:totp_form, to_form(MFA.change_totp(editing_totp)))
  end

  defp generate_qrcode(uri) do
    uri
    |> EQRCode.encode()
    |> EQRCode.svg(width: 256)
    |> raw()
  end

  defp format_secret(secret) do
    secret
    |> Base.encode32(padding: false)
    |> String.graphemes()
    |> Enum.map(&maybe_highlight_digit/1)
    |> Enum.chunk_every(4)
    |> Enum.intersperse(" ")
    |> raw()
  end

  defp highlight_digits(code) do
    code
    |> String.graphemes()
    |> Enum.map(&maybe_highlight_digit/1)
    |> raw()
  end

  defp maybe_highlight_digit(char) do
    case Integer.parse(char) do
      :error -> char
      _ -> ~s(<span class="text-muted">#{char}</span>)
    end
  end

  defp reset_totp_assigns(socket, totp) do
    socket
    |> assign(:current_totp, totp)
    |> assign(:editing_totp, nil)
    |> assign(:qrcode_uri, nil)
  end
end

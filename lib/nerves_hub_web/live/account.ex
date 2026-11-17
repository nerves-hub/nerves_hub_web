defmodule NervesHubWeb.Live.Account do
  use NervesHubWeb, :live_view

  alias NervesHub.Accounts
  alias NervesHub.Accounts.TwoFactor
  alias NervesHub.Accounts.UserToken
  alias NervesHub.Integrations.Slack.Users, as: SlackUsers
  alias NervesHubWeb.Auth
  alias NervesHubWeb.Components.DateTimes
  alias NervesHubWeb.Components.OAuthLinks
  alias NervesHubWeb.CoreComponents
  alias NervesHubWeb.Plugs.Attack

  embed_templates("account_templates/*")

  @impl Phoenix.LiveView
  def mount(_params, session, %{assigns: %{current_scope: scope}} = socket) do
    socket
    # This browser's session, which stays signed in when a change to how the
    # account signs in signs the others out, and when it last proved who it is
    # (`Auth.recently_authenticated?/1`).
    |> assign(:session_token, session["user_token"])
    |> assign(:auth_session, Auth.recent_sign_in_session(session))
    |> assign(:user, scope.user)
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    socket
    |> apply_action(socket.assigns.live_action, params)
    |> noreply()
  end

  # Everything about the account but its access tokens: details, ways to sign
  # in, two-factor, linked accounts and deleting it.
  defp apply_action(socket, :profile, _params) do
    socket
    |> page_title("Profile")
    |> assign(:form, to_form(Ecto.Changeset.change(socket.assigns.user)))
    |> assign(:password_form, nil)
    |> assign(:new_password_form, nil)
    |> assign(:totp, TwoFactor.get(socket.assigns.user))
    |> assign(:recent_until, Auth.recently_authenticated_until(socket.assigns.auth_session))
    |> assign(:slack_links, SlackUsers.list_links(socket.assigns.user))
    |> render_with(&profile_template/1)
  end

  defp apply_action(socket, :tokens, _params) do
    socket
    |> page_title("Access tokens")
    |> assign(:access_tokens, Accounts.get_user_api_tokens(socket.assigns.user))
    |> assign(:access_token_form, to_form(Ecto.Changeset.change(%UserToken{})))
    |> assign(:new_token, nil)
    |> render_with(&tokens_template/1)
  end

  defp apply_action(socket, :delete, _params) do
    socket
    |> page_title("Delete account")
    |> assign(:form, to_form(%{}))
    |> render_with(&delete_account_template/1)
  end

  @impl Phoenix.LiveView
  def handle_event("unlink-slack", %{"link_id" => id}, socket) do
    user = socket.assigns.current_scope.user

    # An id that is not a number names no link of theirs.
    _ =
      with {:ok, id} <- Ecto.Type.cast(:id, id) do
        SlackUsers.unlink(user, id)
      end

    socket
    |> assign(:slack_links, SlackUsers.list_links(user))
    |> put_flash(:info, "The Slack account was unlinked.")
    |> noreply()
  end

  def handle_event("update-details", %{"user" => params}, socket) do
    confirm_url = &url(~p"/account/confirm-email/#{&1}")

    # Any current password sent counts as a try, though only an email change
    # checks it.
    password_tried? = params["current_password"] not in [nil, ""]

    result =
      with :ok <- if(password_tried?, do: check_password_attempts(socket.assigns.user), else: :ok) do
        Accounts.update_user(socket.assigns.user, params, confirm_url)
      end

    case result do
      {:ok, user, nil} ->
        socket
        |> put_user(user)
        |> assign(:form, to_form(Ecto.Changeset.change(user)))
        |> put_flash(:info, "Account updated")
        |> noreply()

      {:ok, user, new_email} ->
        socket
        |> put_user(user)
        |> assign(:form, to_form(Ecto.Changeset.change(user)))
        |> put_flash(:info, "We've emailed a link to #{new_email}. Your email address will change when you follow it.")
        |> noreply()

      {:error, :too_many_attempts} ->
        socket
        |> assign(:form, to_form(too_many_attempts(socket.assigns.user, params)))
        |> noreply()

      {:error, changeset} ->
        socket
        |> assign(:form, to_form(changeset))
        |> noreply()
    end
  end

  @impl Phoenix.LiveView
  def handle_event("update-password", %{"user" => %{"current_password" => password} = user_params}, socket) do
    user_params = Map.delete(user_params, "current_password")

    reset_url = &url(~p"/password-reset/#{&1}")
    user = socket.assigns.current_scope.user

    result =
      with :ok <- check_password_attempts(user) do
        Accounts.update_user_password(user, password, user_params, reset_url)
      end

    case result do
      {:ok, user} ->
        socket
        |> put_user(user)
        |> assign(:password_form, nil)
        |> put_flash(:info, "Your password is changed.")
        |> noreply()

      {:error, :too_many_attempts} ->
        socket
        |> assign(:password_form, to_form(too_many_attempts(user, user_params)))
        |> noreply()

      {:error, changeset} ->
        socket
        |> assign(:password_form, to_form(changeset))
        |> noreply()
    end
  end

  # Adding or removing a way to sign in needs a recent sign-in, the same
  # whichever way the account signs in, so a signed in browser alone can't lock
  # its owner out or let somebody else keep the account.
  # Changing the password asks for the old one, so it needs no recent sign-in.
  def handle_event("start-change-password", _params, socket) do
    socket
    |> assign(:password_form, to_form(Accounts.change_user_password(socket.assigns.user)))
    |> noreply()
  end

  def handle_event("cancel-change-password", _params, socket) do
    socket |> assign(:password_form, nil) |> noreply()
  end

  def handle_event("start-set-password", _params, socket) do
    with_recent_sign_in(socket, fn socket ->
      socket
      |> assign(:new_password_form, to_form(Accounts.change_user_password(socket.assigns.user)))
      |> noreply()
    end)
  end

  def handle_event("cancel-set-password", _params, socket) do
    socket |> assign(:new_password_form, nil) |> noreply()
  end

  def handle_event("set-password", %{"user" => params}, socket) do
    with_recent_sign_in(socket, fn socket ->
      reset_url = &url(~p"/password-reset/#{&1}")

      case Accounts.set_user_password(socket.assigns.user, params, reset_url) do
        {:ok, user} ->
          socket
          |> put_user(user)
          |> assign(:new_password_form, nil)
          |> put_flash(:info, "Your password is set. You can sign in with it as well as with Google.")
          |> noreply()

        {:error, %Ecto.Changeset{} = changeset} ->
          socket |> assign(:new_password_form, to_form(changeset)) |> noreply()

        {:error, :already_set} ->
          socket |> assign(:new_password_form, nil) |> noreply()
      end
    end)
  end

  def handle_event("remove-password", _params, socket) do
    with_recent_sign_in(socket, fn socket ->
      case Accounts.remove_password(socket.assigns.user, socket.assigns.session_token) do
        {:ok, user} ->
          socket
          |> put_user(user)
          |> put_flash(
            :info,
            "Your password is removed, so you sign in with Google. Your other browser sessions were signed out."
          )
          |> noreply()

        {:error, reason} ->
          socket |> put_flash(:error, sign_in_method_error(reason)) |> noreply()
      end
    end)
  end

  def handle_event("disconnect-google", _params, socket) do
    with_recent_sign_in(socket, fn socket ->
      case Accounts.disconnect_google(socket.assigns.user, socket.assigns.session_token) do
        {:ok, user} ->
          socket
          |> put_user(user)
          |> put_flash(
            :info,
            "Your Google account is disconnected, so you sign in with your password. Your other browser sessions were signed out."
          )
          |> noreply()

        {:error, reason} ->
          socket |> put_flash(:error, sign_in_method_error(reason)) |> noreply()
      end
    end)
  end

  def handle_event("delete", params, %{assigns: %{current_scope: scope}} = socket) do
    if params["confirm_email"] == scope.user.email do
      {:ok, _} = Accounts.remove_account(scope.user.id)

      socket
      |> redirect(to: ~p"/login")
      |> put_flash(:error, "Your account has successfully been deleted")
      |> noreply()
    else
      socket
      |> put_flash(:error, "Please type #{scope.user.email} to confirm.")
      |> noreply()
    end
  end

  def handle_event("generate-access-token", %{"user_token" => params}, socket) do
    %{assigns: %{current_scope: %{user: user}}} = socket

    token = Accounts.create_user_api_token(user, params["note"])

    socket
    |> put_flash(:info, "Token created")
    |> assign(:new_token, token)
    |> assign(:access_tokens, Accounts.get_user_api_tokens(user))
    |> push_event("close-modal", %{id: "new-access-token"})
    |> noreply()
  end

  def handle_event("delete-access-token", %{"access_token_id" => token_id}, socket) do
    %{assigns: %{current_scope: %{user: user}}} = socket

    case Accounts.delete_user_token(user, token_id) do
      {:ok, _token} ->
        socket
        |> put_flash(:info, "Token deleted")
        |> assign(:access_tokens, Accounts.get_user_api_tokens(user))
        |> assign(:new_token, nil)
        |> noreply()

      {:error, _changeset} ->
        socket
        |> put_flash(:error, "Could not delete token, please contact support.")
        |> assign(:new_token, nil)
        |> noreply()
    end
  end

  attr(:id, :string, required: true)
  attr(:open, :boolean, default: false, doc: "whether to show `inner_block` under the row")
  slot(:icon)
  slot(:title, required: true)
  slot(:badge)
  slot(:description, required: true)
  slot(:actions, doc: "buttons at the end of the row, in a column of their own so rows line up")
  slot(:inner_block, doc: "anything opened under the row, such as a form")

  # A row of a list on the account pages: a way to sign in, a token, a linked
  # account.
  defp account_row(assigns) do
    ~H"""
    <div id={@id} class="flex flex-col gap-4 p-4 sm:px-5">
      <div class="flex flex-wrap items-center gap-x-3.5 gap-y-3">
        <span :if={@icon != []} class="flex size-9 flex-none items-center justify-center rounded-full bg-surface-muted text-content-muted">
          {render_slot(@icon)}
        </span>
        <div class="flex min-w-0 flex-1 basis-56 flex-col gap-0.75">
          <div class="flex flex-wrap items-center gap-2">
            <h3 class="text-sm/4.5 font-medium text-content-strong">{render_slot(@title)}</h3>
            {render_slot(@badge)}
          </div>
          <p class="text-ui/4.5 text-content-muted">{render_slot(@description)}</p>
        </div>
        <div :if={@actions != []} class="flex w-full flex-none justify-end gap-2 sm:w-50">
          {render_slot(@actions)}
        </div>
      </div>
      <div :if={@open} class="border-t border-line-default pt-4 sm:pl-12.5">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp with_recent_sign_in(socket, fun) do
    if Auth.recently_authenticated?(socket.assigns.auth_session) do
      fun.(socket)
    else
      socket
      |> redirect(to: ~p"/account/confirm?#{[return_to: ~p"/account"]}")
      |> noreply()
    end
  end

  # Guessing the password here would get round the limit on `/account/confirm`,
  # where it buys a recent sign-in, so tries here count against the same one.
  defp check_password_attempts(user) do
    case Attack.confirm_identity_throttle(user.id) do
      {:allow, _data} -> :ok
      {:block, _data} -> {:error, :too_many_attempts}
    end
  end

  # The form as it was sent, but for the password, which the error goes under.
  defp too_many_attempts(user, params) do
    user
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.cast(Map.put(params, "current_password", ""), [
      :name,
      :email,
      :password,
      :password_confirmation,
      :current_password
    ])
    |> Ecto.Changeset.add_error(
      :current_password,
      "Too many tries. To keep your account safe, wait ten minutes, then try again."
    )
    |> Map.put(:action, :validate)
  end

  # The page reads how the account signs in from both. The header counts the
  # organizations preloaded at mount, which an updated user doesn't carry.
  defp put_user(socket, user) do
    user = %{user | orgs: socket.assigns.user.orgs}

    socket
    |> assign(:user, user)
    |> assign(:current_scope, %{socket.assigns.current_scope | user: user})
  end

  defp sign_in_method_error(:last_sign_in_method), do: "That's the only way you can sign in, so it can't be removed."

  defp sign_in_method_error(_reason), do: "That couldn't be changed. Reload the page and try again."
end

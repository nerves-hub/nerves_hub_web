defmodule NervesHubWeb.Live.Account do
  use NervesHubWeb, :live_view

  alias NervesHub.Accounts
  alias NervesHub.Accounts.UserToken
  alias NervesHubWeb.CoreComponents
  alias NervesHubWeb.LayoutView.DateTimeFormat

  embed_templates("account_templates/*")

  @impl Phoenix.LiveView
  def mount(_params, _session, %{assigns: %{current_scope: scope}} = socket) do
    socket
    |> assign(:password_changeset, Accounts.change_user_password(scope.user))
    |> assign(:access_tokens, Accounts.get_user_api_tokens(scope.user))
    |> assign(:access_token_form, to_form(Ecto.Changeset.change(%UserToken{})))
    |> assign(:user, scope.user)
    |> assign(:mfa_setup, nil)
    |> assign(:mfa_recovery_codes, nil)
    |> assign(:mfa_password_form, to_form(%{}, as: :mfa))
    |> assign(:mfa_code_form, to_form(%{}, as: :mfa))
    |> assign(:new_token, nil)
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    socket
    |> apply_action(socket.assigns.live_action, params)
    |> noreply()
  end

  defp apply_action(socket, :edit, _params) do
    socket
    |> page_title("Account Settings")
    |> assign(:form, to_form(Ecto.Changeset.change(socket.assigns.current_scope.user)))
    |> render_with(&edit_account_template/1)
  end

  defp apply_action(socket, :delete, _params) do
    socket
    |> page_title("Delete Account")
    |> assign(:form, to_form(%{}))
    |> render_with(&delete_account_template/1)
  end

  @impl Phoenix.LiveView
  def handle_event("update-details", %{"user" => params}, socket) do
    socket.assigns.current_scope.user
    |> Accounts.update_user(params)
    |> case do
      {:ok, user} ->
        socket
        |> assign(:user, user)
        |> put_flash(:info, "Account updated")
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

    socket.assigns.current_scope.user
    |> Accounts.update_user_password(password, user_params, reset_url)
    |> case do
      {:ok, user} ->
        socket
        |> assign(:user, user)
        |> put_flash(:info, "Account updated")
        |> noreply()

      {:error, changeset} ->
        socket
        |> assign(:password_changeset, changeset)
        |> noreply()
    end
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

  def handle_event("start-mfa-setup", %{"mfa" => %{"current_password" => current_password}}, socket) do
    case Accounts.start_mfa_setup(socket.assigns.user, current_password) do
      {:ok, setup} ->
        socket
        |> assign(:mfa_setup, setup)
        |> assign(:mfa_recovery_codes, nil)
        |> noreply()

      {:error, :invalid_password} ->
        socket
        |> put_flash(:error, "Current password is not correct")
        |> noreply()
    end
  end

  def handle_event("confirm-mfa-setup", _params, %{assigns: %{mfa_setup: nil}} = socket) do
    socket
    |> put_flash(:error, "Start MFA setup before confirming a code")
    |> noreply()
  end

  def handle_event("confirm-mfa-setup", %{"mfa" => %{"code" => code}}, socket) do
    case Accounts.confirm_mfa_setup(socket.assigns.user, socket.assigns.mfa_setup.secret, code) do
      {:ok, user, recovery_codes} ->
        socket
        |> assign(:user, user)
        |> assign(:mfa_setup, nil)
        |> assign(:mfa_recovery_codes, recovery_codes)
        |> put_flash(:info, "MFA enabled")
        |> noreply()

      {:error, :invalid_code} ->
        socket
        |> put_flash(:error, "Invalid authentication code")
        |> noreply()
    end
  end

  def handle_event("disable-mfa", %{"mfa" => %{"current_password" => current_password}}, socket) do
    case Accounts.disable_mfa(socket.assigns.user, current_password) do
      {:ok, user} ->
        socket
        |> assign(:user, user)
        |> assign(:mfa_recovery_codes, nil)
        |> put_flash(:info, "MFA disabled")
        |> noreply()

      {:error, :invalid_password} ->
        socket
        |> put_flash(:error, "Current password is not correct")
        |> noreply()
    end
  end
end

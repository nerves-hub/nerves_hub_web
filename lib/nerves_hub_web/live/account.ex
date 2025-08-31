defmodule NervesHubWeb.Live.Account do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Accounts

  embed_templates("account_templates/*")

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket
    |> assign(:password_changeset, Accounts.change_user_password(socket.assigns.user))
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
    |> assign(:form, to_form(Ecto.Changeset.change(socket.assigns.user)))
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
    socket.assigns.user
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

    socket.assigns.user
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

  def handle_event("delete", params, socket) do
    if params["confirm_email"] == socket.assigns.user.email do
      {:ok, _} = Accounts.remove_account(socket.assigns.user.id)

      socket
      |> redirect(to: ~p"/login")
      |> put_flash(:error, "Your account has successfully been deleted")
      |> noreply()
    else
      socket
      |> put_flash(:error, "Please type #{socket.assigns.user.email} to confirm.")
      |> noreply()
    end
  end
end

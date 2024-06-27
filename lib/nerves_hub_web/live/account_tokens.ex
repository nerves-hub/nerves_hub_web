defmodule NervesHubWeb.Live.AccountTokens do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Accounts
  alias NervesHub.Accounts.UserToken
  alias NervesHubWeb.LayoutView.DateTimeFormat

  embed_templates("account_tokens_templates/*")

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
    |> page_title("Account Access Tokens")
    |> assign_access_tokens()
    |> render_with(&list_account_tokens_template/1)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> page_title("New Account Access Token")
    |> assign(:form, to_form(Ecto.Changeset.change(%UserToken{})))
    |> render_with(&new_account_tokens_template/1)
  end

  @impl Phoenix.LiveView
  def handle_event("create_account_token", %{"user_token" => params}, socket) do
    user = socket.assigns.user

    case Accounts.create_user_token(user, params["note"]) do
      {:ok, %{token: token}} ->
        socket
        |> put_flash(:info, "Token created : #{token}")
        |> push_navigate(to: ~p"/account/tokens")
        |> noreply()

      {:error, changeset} ->
        socket
        |> put_flash(:error, "There was an issue creating the token")
        |> assign(:form, to_form(changeset))
        |> noreply()
    end
  end

  def handle_event("delete", %{"access_token_id" => token_id}, socket) do
    user = socket.assigns.user

    case Accounts.delete_user_token(user, token_id) do
      {:ok, _token} ->
        socket
        |> put_flash(:info, "Token deleted")
        |> assign_access_tokens()
        |> noreply()

      {:error, _changeset} ->
        socket
        |> put_flash(:error, "Could not delete token, please contact support.")
        |> noreply()
    end
  end

  defp assign_access_tokens(socket) do
    assign(socket, :tokens, Accounts.get_user_tokens(socket.assigns.user))
  end
end

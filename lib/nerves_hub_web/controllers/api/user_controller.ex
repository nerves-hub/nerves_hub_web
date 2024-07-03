defmodule NervesHubWeb.API.UserController do
  use NervesHubWeb, :api_controller

  alias NervesHub.Accounts

  action_fallback(NervesHubWeb.API.FallbackController)

  def me(%{assigns: %{user: user}} = conn, _params) do
    render(conn, "show.json", user: user)
  end

  def auth(conn, %{"email" => email, "password" => password}) do
    with {:ok, user} <- Accounts.authenticate(email, password) do
      render(conn, "show.json", user: user)
    end
  end

  def login(conn, %{"email" => email, "password" => password, "note" => note}) do
    with {:ok, user} <- Accounts.authenticate(email, password),
         {:ok, %{token: token}} <- Accounts.create_user_token(user, note) do
      render(conn, "show.json", user: user, token: token)
    end
  end
end

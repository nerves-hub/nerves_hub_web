defmodule NervesHubWeb.API.UserController do
  use NervesHubWeb, :api_controller

  alias NervesHub.Accounts

  def me(%{assigns: %{user: user}} = conn, _params) do
    render(conn, :show, user: user)
  end

  def auth(conn, %{"email" => email, "password" => password}) do
    with {:ok, user} <- Accounts.authenticate(email, password) do
      render(conn, :show, user: user)
    end
  end

  def login(conn, %{"email" => email, "password" => password, "note" => note}) do
    with {:ok, user} <- Accounts.authenticate(email, password),
         token <- Accounts.create_user_api_token(user, note) do
      render(conn, :show, user: user, token: token)
    end
  end
end

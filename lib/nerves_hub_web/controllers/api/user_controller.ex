defmodule NervesHubWeb.API.UserController do
  use NervesHubWeb, :api_controller

  alias NervesHub.Accounts

  action_fallback(NervesHubWeb.API.FallbackController)

  def me(%{assigns: %{user: user}} = conn, _params) do
    render(conn, "show.json", user: user)
  end

  def auth(conn, %{"password" => password} = opts) do
    username_or_email = opts["username"] || opts["email"]

    with {:ok, user} <- Accounts.authenticate(username_or_email, password) do
      render(conn, "show.json", user: user)
    end
  end

  def login(conn, %{"password" => password, "note" => note} = opts) do
    username_or_email = opts["username"] || opts["email"]

    with {:ok, user} <- Accounts.authenticate(username_or_email, password),
         {:ok, %{token: token}} <- Accounts.create_user_token(user, note) do
      render(conn, "show.json", user: user, token: token)
    end
  end
end

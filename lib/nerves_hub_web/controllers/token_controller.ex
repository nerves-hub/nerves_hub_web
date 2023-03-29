defmodule NervesHubWeb.TokenController do
  use NervesHubWeb, :controller

  alias NervesHub.Accounts
  alias NervesHub.Accounts.UserToken
  alias NervesHub.Repo

  def index(conn, _params) do
    user = Repo.preload(conn.assigns.user, [:user_tokens])

    conn
    |> assign(:user_tokens, user.user_tokens)
    |> render("index.html")
  end

  def new(conn, _params) do
    conn
    |> assign(:changeset, UserToken.create_changeset(conn.assigns.user, %{}))
    |> render("new.html")
  end

  def create(conn, %{"user_token" => %{"note" => note}}) do
    user = conn.assigns.user

    case Accounts.create_user_token(user, note) do
      {:ok, %{token: token}} ->
        conn
        |> put_flash(:info, "Token Created: #{token}")
        |> redirect(to: Routes.token_path(conn, :index, user.username))

      {:error, _changeset} ->
        conn
        |> put_flash(:info, "There was an issue creating the token")
        |> redirect(to: Routes.token_path(conn, :new, user.username))
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.user

    with {:ok, token} <- Accounts.get_user_token(user, id),
         {:ok, _token} <- Repo.delete(token) do
      conn
      |> put_flash(:info, "Token deleted!")
      |> redirect(to: Routes.token_path(conn, :index, user.username))
    else 
      _ ->
        conn
        |> put_flash(:error, "Could not delete token")
        |> redirect(to: Routes.token_path(conn, :index, user.username))
    end
  end
end

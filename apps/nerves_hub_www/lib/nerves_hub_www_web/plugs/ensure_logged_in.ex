defmodule NervesHubWWWWeb.Plugs.EnsureLoggedIn do
  import Plug.Conn

  alias Phoenix.Controller
  alias Plug.Conn
  alias NervesHubCore.Accounts

  @session_key "auth_user_id"

  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    conn
    |> Conn.get_session(@session_key)
    |> case do
      nil -> nil
      user_id -> Accounts.get_user(user_id)
    end
    |> case do
      {:ok, user} ->
        [default_org | _] = user.orgs

        conn
        |> assign(:user, user)
        |> assign(:org, default_org)

      _ ->
        conn
        |> Controller.put_flash(:error, "You must login to access this page.")
        |> Controller.redirect(to: "/")
        |> halt()
    end
  end
end

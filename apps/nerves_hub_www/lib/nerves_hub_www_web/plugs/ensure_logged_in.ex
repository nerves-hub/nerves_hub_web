defmodule NervesHubWWWWeb.Plugs.EnsureLoggedIn do
  import Plug.Conn

  alias Phoenix.Controller
  alias Plug.Conn
  alias NervesHubWebCore.Accounts

  @session_key "auth_user_id"

  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    conn
    |> Conn.get_session(@session_key)
    |> case do
      nil -> nil
      user_id -> Accounts.get_user_with_all_orgs(user_id)
    end
    |> case do
      {:ok, user} ->
        {:ok, current_org} =
          get_session(conn, "current_org_id") |> Accounts.get_org_with_org_keys()

        limit = Accounts.get_org_limit_by_org_id(current_org.id)

        conn
        |> assign(:user, user)
        |> assign(:current_org, current_org)
        |> assign(:current_limit, limit)
        |> assign(:user_token, Phoenix.Token.sign(conn, "user salt", user.id))

      _ ->
        conn
        |> Controller.put_flash(:error, "You must login to access this page.")
        |> Controller.redirect(to: "/")
        |> halt()
    end
  end
end

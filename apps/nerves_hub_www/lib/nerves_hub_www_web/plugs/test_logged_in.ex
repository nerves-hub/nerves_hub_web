defmodule NervesHubWWWWeb.Plugs.TestLoggedIn do
  import Plug.Conn

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
        conn
        |> assign(:user, user)
        |> assign(:org, user.org)

      _ ->
        conn
    end
  end
end
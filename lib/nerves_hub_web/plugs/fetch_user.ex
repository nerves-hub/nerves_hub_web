defmodule NervesHubWeb.Plugs.FetchUser do
  import Plug.Conn

  alias NervesHub.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, "auth_user_id") do
      nil ->
        conn

      user_id ->
        case Accounts.get_user_with_all_orgs(user_id) do
          {:ok, user} ->
            conn
            |> assign(:user, user)
            |> assign(:orgs, user.orgs)
            |> assign(:user_token, Phoenix.Token.sign(conn, "user salt", user.id))

          _ ->
            conn
        end
    end
  end
end


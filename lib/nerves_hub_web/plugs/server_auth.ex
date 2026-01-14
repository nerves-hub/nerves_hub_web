defmodule NervesHubWeb.Plugs.ServerAuth do
  @behaviour Oban.Web.Resolver

  use NervesHubWeb, :plug

  @impl Plug
  def init(_opts), do: []

  @impl Plug
  def call(conn, _opts) do
    case conn.assigns.user do
      %{server_role: role} when not is_nil(role) ->
        conn

      _user ->
        conn
        |> put_session(:login_redirect_path, conn.request_path)
        |> put_flash(:error, "Unauthorized")
        |> redirect(to: "/")
        |> halt()
    end
  end

  @impl Oban.Web.Resolver
  def resolve_user(conn), do: conn.assigns.user

  @impl Oban.Web.Resolver
  def resolve_access(user) do
    case user.server_role do
      :admin ->
        :all

      _ ->
        :read_only
    end
  end
end

defmodule NervesHubWeb.API.Plugs.RequireAuthenticatedUser do
  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    if get_in(conn.assigns.current_scope.user) do
      conn
    else
      raise NervesHubWeb.UnauthorizedError
    end
  end
end

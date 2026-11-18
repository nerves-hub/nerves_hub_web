defmodule NervesHubWeb.API.Plugs.FetchCurrentScope do
  @moduledoc """
  Sets `current_scope` from the request's API token, which is either a user API
  token or a product API key.

  Without a valid token the scope has nobody in it, and the routes that need
  one refuse the request: `NervesHubWeb.API.Plugs.RequireAuthenticatedUser`, or
  `NervesHubWeb.API.Plugs.RequireAuthenticatedUserOrApiKey` on the routes a key
  may use.
  """

  import Plug.Conn

  alias NervesHub.Accounts.Scope
  alias NervesHubWeb.Auth

  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    with {:ok, token} <- get_req_token(conn),
         {:ok, scope} <- Auth.fetch_api_scope(token) do
      assign(conn, :current_scope, scope)
    else
      _ ->
        assign(conn, :current_scope, Scope.for_user(nil))
    end
  end

  defp get_req_token(conn) do
    with [header] <- get_req_header(conn, "authorization"),
         {scheme, token} <- get_scheme_and_token(header),
         true <- String.downcase(scheme) in ["token", "bearer"] do
      {:ok, token}
    end
  end

  defp get_scheme_and_token(header) do
    case String.split(header, " ") do
      [scheme, token | _] ->
        {scheme, token}

      _ ->
        :invalid_token_format
    end
  end
end

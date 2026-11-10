defmodule NervesHub.Telemetry.RequestPath do
  @moduledoc """
  A request's path as it's safe to record, in the request log and on traces.

  Some routes carry a secret in the path itself, as a `:token` parameter: the
  token a CLI polls its login with, which collects an API token once someone
  confirms the login, and the links in password reset, invite and email
  confirmation emails. Anyone who can read a recorded path can use the token in
  it, so the token is recorded as `[FILTERED]`, the way Phoenix filters a
  parameter.

  The token is found in the parameters the router matched, so a new route with
  a `:token` parameter is covered without being listed here. A path that matched
  no route is recorded as it came, since nothing will accept a token in it.
  """

  @filtered "[FILTERED]"

  @doc """
  The request's path, with any `:token` path parameter replaced by `[FILTERED]`.

  The query string isn't included.
  """
  @spec recordable(Plug.Conn.t() | %{request_path: String.t()}) :: String.t()
  def recordable(%{path_params: %{"token" => token}} = conn) when is_binary(token) do
    segments =
      for segment <- conn.script_name ++ conn.path_info do
        if segment == token, do: @filtered, else: segment
      end

    "/" <> Enum.join(segments, "/")
  end

  def recordable(%{request_path: request_path}), do: request_path
end

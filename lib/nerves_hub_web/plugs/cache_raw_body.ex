defmodule NervesHubWeb.Plugs.CacheRawBody do
  @moduledoc """
  A `Plug.Parsers` body reader that keeps a copy of the raw body, as
  `conn.assigns.raw_body`, for requests whose signature covers it: those
  other services send to `/integrations/`, such as Slack's (see
  `NervesHubWeb.Integrations.Slack.VerifyRequest`).

  Other requests are read as `Plug.Conn.read_body/2` would, and keep nothing,
  so a large upload is not held in memory twice.
  """

  @paths ["/integrations/"]

  @spec read_body(Plug.Conn.t(), keyword()) :: {:ok | :more, binary(), Plug.Conn.t()} | {:error, term()}
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {status, body, conn} when status in [:ok, :more] ->
        {status, body, keep(conn, body)}

      error ->
        error
    end
  end

  defp keep(%Plug.Conn{request_path: path} = conn, body) do
    if String.starts_with?(path, @paths) do
      Plug.Conn.assign(conn, :raw_body, (conn.assigns[:raw_body] || "") <> body)
    else
      conn
    end
  end
end

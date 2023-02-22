defmodule NervesHubDeviceWeb.Plugs.Logger do
  require Logger

  def init(opts) do
    Keyword.get(opts, :log, :info)
  end

  def call(conn, level) do
    start = System.monotonic_time()

    Plug.Conn.register_before_send(conn, fn conn ->
      Logger.log(level, fn ->
        stop = System.monotonic_time()
        duration = System.convert_time_unit(stop - start, :native, :millisecond)

        Logfmt.encode(
          duration: duration,
          method: conn.method,
          path: request_path(conn),
          status: conn.status,
          remote_ip: formatted_ip(conn.remote_ip)
        )
      end)

      conn
    end)
  end

  def request_path(%{request_path: request_path, query_string: query_string})
      when query_string not in ["", nil],
      do: request_path <> "?" <> query_string

  def request_path(%{request_path: request_path}), do: request_path
  def request_path(_), do: nil

  defp formatted_ip(ip) do
    to_string(:inet_parse.ntoa(ip))
  end
end

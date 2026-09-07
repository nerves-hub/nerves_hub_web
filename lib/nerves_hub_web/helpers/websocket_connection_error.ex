defmodule NervesHub.Helpers.WebsocketConnectionError do
  import Plug.Conn

  @message "no certificate pair or shared secrets connection settings were provided"

  def handle_error(conn, :no_auth) do
    conn
    |> put_resp_header("nh-connection-error-reason", @message)
    |> send_resp(401, @message)
  end

  @unavailable "the platform could not be reached to authenticate this device"

  # Not the device's fault, and worth distinguishing: 401 tells it to check its
  # credentials, when what it should do is try again shortly.
  def handle_error(conn, :platform_unavailable) do
    conn
    |> put_resp_header("nh-connection-error-reason", @unavailable)
    |> send_resp(503, @unavailable)
  end

  # A device connected to the wrong host. Point it at the device websocket host,
  # keeping the path and query it asked for so it lands on the same socket.
  def handle_error(conn, {:redirect, host}) do
    conn
    |> put_resp_header("location", redirect_url(conn, host))
    |> send_resp(301, "")
  end

  def handle_error(conn, _reason), do: send_resp(conn, 401, "")

  defp redirect_url(conn, host) do
    %URI{scheme: scheme, host: host, port: port, path: path} = URI.parse(prefix_scheme(host))

    %URI{
      scheme: scheme,
      host: host,
      port: port,
      path: path || conn.request_path,
      query: (conn.query_string != "" && conn.query_string) || nil
    }
    |> URI.to_string()
  end

  # `:devices_websocket_url` is usually a bare host, but tolerate a full URL.
  defp prefix_scheme(host) do
    if String.contains?(host, "://"), do: host, else: "wss://" <> host
  end
end

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

  def handle_error(conn, _reason), do: send_resp(conn, 401, "")
end

defmodule NervesHub.Helpers.WebsocketConnectionError do
  import Plug.Conn

  @message "no certificate pair or shared secrets connection settings were provided"

  def handle_error(conn, :no_auth) do
    conn
    |> put_resp_header("nh-connection-error-reason", @message)
    |> send_resp(401, @message)
  end

  def handle_error(conn, _reason), do: send_resp(conn, 401, "")
end

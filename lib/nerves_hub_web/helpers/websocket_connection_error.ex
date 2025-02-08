defmodule NervesHub.Helpers.WebsocketConnectionError do
  import Plug.Conn

  @no_auth_message "no certificate pair or shared secrets connection settings were provided"
  @check_uri_message "incorrect uri used, please contact support"

  def handle_error(conn, :no_auth) do
    conn
    |> put_resp_header("nh-connection-error-reason", @no_auth_message)
    |> send_resp(401, @no_auth_message)
  end

  def handle_error(conn, :check_uri) do
    conn
    |> put_resp_header("nh-connection-error-reason", @check_uri_message)
    |> send_resp(404, @check_uri_message)
  end

  def handle_error(conn, _reason), do: send_resp(conn, 401, "")
end

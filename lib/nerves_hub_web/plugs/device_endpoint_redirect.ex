defmodule NervesHubWeb.Plugs.DeviceEndpointRedirect do
  use NervesHubWeb, :plug

  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    location = Application.get_env(:nerves_hub, :device_endpoint_redirect)

    Logger.info("Invalid request to #{conn.request_path}, redirecting to #{location}")

    conn
    |> put_resp_header("location", location)
    |> send_resp(301, "")
    |> halt
  end
end

defmodule NervesHubDeviceWeb.Plugs.Device do
  import Plug.Conn

  alias NervesHubCore.{Devices, Certificate}

  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    peer_data = Plug.Conn.get_peer_data(conn)

    with {:ok, cert} <- Map.fetch(peer_data, :ssl_cert),
         {:ok, cert} <- X509.Certificate.from_der(cert),
         serial <- Certificate.get_serial_number(cert),
         {:ok, cert} <- Devices.get_device_certificate_by_serial(serial),
         {:ok, device} <- Devices.get_device_by_certificate(cert) do
      assign(conn, :device, device)
    else
      _err ->
        conn
        |> put_resp_header("content-type", "application/json")
        |> send_resp(403, Jason.encode!(%{status: "forbidden"}))
        |> halt()
    end
  end
end

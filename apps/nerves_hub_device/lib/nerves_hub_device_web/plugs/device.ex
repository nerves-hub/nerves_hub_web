defmodule NervesHubDeviceWeb.Plugs.Device do
  import Plug.Conn

  alias NervesHubWebCore.Devices
  alias NervesHubWebCore.Firmwares

  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    peer_data = Plug.Conn.get_peer_data(conn)

    with {:ok, cert} <- Map.fetch(peer_data, :ssl_cert),
         {:ok, cert} <- X509.Certificate.from_der(cert),
         {:ok, cert} <- NervesHubDevice.SSL.verify_device(cert),
         {:ok, device} <- Devices.get_device_by_certificate(cert),
         {:ok, metadata} <- Firmwares.metadata_from_conn(conn),
         {:ok, device} <- Devices.update_firmware_metadata(device, metadata),
         {:ok, device} <- Devices.device_connected(device) do
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

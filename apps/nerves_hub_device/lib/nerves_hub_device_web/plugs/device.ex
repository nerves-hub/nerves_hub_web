defmodule NervesHubDeviceWeb.Plugs.Device do
  import Plug.Conn

  alias NervesHubWebCore.Devices

  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    peer_data = Plug.Conn.get_peer_data(conn)

    with {:ok, cert} <- Map.fetch(peer_data, :ssl_cert),
         {:ok, cert} <- X509.Certificate.from_der(cert),
         {:ok, cert} <- NervesHubDevice.SSL.verify_device(cert),
         {:ok, device} <- Devices.get_device_by_certificate(cert),
         uuid_header <- get_req_header(conn, "x-nerveshub-uuid"),
         {:ok, device} <- update_last_known_firmware(uuid_header, device),
         {:ok, device} <- Devices.received_communication(device) do
      assign(conn, :device, device)
    else
      _err ->
        conn
        |> put_resp_header("content-type", "application/json")
        |> send_resp(403, Jason.encode!(%{status: "forbidden"}))
        |> halt()
    end
  end

  defp update_last_known_firmware([], device), do: {:ok, device}

  defp update_last_known_firmware([fw_uuid], device) do
    Devices.update_last_known_firmware(device, fw_uuid)
  end
end

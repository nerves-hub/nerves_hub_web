defmodule NervesHubAPIWeb.DeviceController do
  use NervesHubAPIWeb, :controller

  alias NervesHubWebCore.{Certificate, Devices, Devices.DeviceCertificate}

  action_fallback(NervesHubAPIWeb.FallbackController)

  def index(%{assigns: %{org: org}} = conn, _params) do
    conn
    |> render(
      "index.json",
      devices: Devices.get_devices(org)
    )
  end

  def create(%{assigns: %{org: org}} = conn, params) do
    params = Map.put(params, "org_id", org.id)

    with {:ok, device} <- Devices.create_device(params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", device_path(conn, :show, org.name, device.identifier))
      |> render("show.json", device: device)
    end
  end

  def show(%{assigns: %{org: org}} = conn, %{"device_identifier" => identifier}) do
    with {:ok, device} <- Devices.get_device_by_identifier(org, identifier) do
      render(conn, "show.json", device: device)
    end
  end

  def delete(%{assigns: %{org: org}} = conn, %{
        "device_identifier" => identifier
      }) do
    {:ok, device} = Devices.get_device_by_identifier(org, identifier)
    {:ok, _device} = Devices.delete_device(device)

    send_resp(conn, :no_content, "")
  end

  def update(%{assigns: %{org: org}} = conn, %{"device_identifier" => identifier} = params) do
    with {:ok, device} <- Devices.get_device_by_identifier(org, identifier),
         {:ok, updated_device} <- Devices.update_device(device, params) do
      conn
      |> put_status(201)
      |> render("show.json", device: updated_device)
    end
  end

  def auth(%{assigns: %{org: org}} = conn, %{"certificate" => cert64}) do
    with {:ok, cert_pem} <- Base.decode64(cert64),
         {:ok, cert} <- X509.Certificate.from_pem(cert_pem),
         serial <- Certificate.get_serial_number(cert),
         {:ok, %DeviceCertificate{device_id: device_id}} <-
           Devices.get_device_certificate_by_serial(serial),
         {:ok, device} <- Devices.get_device_by_org(org, device_id) do
      conn
      |> put_status(200)
      |> render("show.json", device: device)
    else
      _e ->
        conn
        |> send_resp(403, Jason.encode!(%{status: "Unauthorized"}))
    end
  end
end

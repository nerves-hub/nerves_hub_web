defmodule NervesHubWeb.API.DeviceCertificateController do
  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Certificate
  alias NervesHub.Devices

  security([%{}, %{"bearer_auth" => []}])
  tags(["Device Certificates"])

  plug(:validate_role, [org: :manage] when action in [:create, :delete])
  plug(:validate_role, [org: :view] when action in [:index, :show])

  operation(:index, summary: "List all Certificates for a Device")

  def index(%{assigns: %{org: org}} = conn, %{"identifier" => identifier}) do
    with {:ok, device} <- Devices.get_device_by_identifier(org, identifier) do
      device_certificates = Devices.get_device_certificates(device)
      render(conn, :index, device_certificates: device_certificates)
    end
  end

  operation(:show, summary: "Show a Certificate for a Device")

  def show(%{assigns: %{device: device}} = conn, %{"serial" => serial}) do
    with {:ok, device_certificate} <-
           Devices.get_device_certificate_by_device_and_serial(device, serial) do
      render(conn, :show, device_certificate: device_certificate)
    end
  end

  operation(:create, summary: "Create a Certificate for a Device")

  def create(%{assigns: %{org: org, product: product, device: device}} = conn, %{"cert" => cert64}) do
    with {:ok, cert_pem} <- Base.decode64(cert64),
         {:ok, cert} <- X509.Certificate.from_pem(cert_pem),
         serial <- Certificate.get_serial_number(cert),
         aki <- Certificate.get_aki(cert),
         ski <- Certificate.get_ski(cert),
         {not_before, not_after} <- Certificate.get_validity(cert),
         params <- %{
           serial: serial,
           aki: aki,
           ski: ski,
           not_before: not_before,
           not_after: not_after,
           der: X509.Certificate.to_der(cert)
         },
         {:ok, device_certificate} <- Devices.create_device_certificate(device, params) do
      conn
      |> put_status(:created)
      |> put_resp_header(
        "location",
        Routes.api_device_certificate_path(
          conn,
          :show,
          org.name,
          product.name,
          device.identifier,
          device_certificate.serial
        )
      )
      |> render(:show, device_certificate: device_certificate)
    else
      {:error, :not_found} ->
        {:error, {:certificate_decoding_error, "Error decoding certificate"}}

      e ->
        e
    end
  end

  operation(:delete, summary: "Delete a Device's Certificate")

  def delete(%{assigns: %{device: device}} = conn, %{"serial" => serial}) do
    with {:ok, device_certificate} <-
           Devices.get_device_certificate_by_device_and_serial(device, serial),
         {:ok, _device_certificate} <- Devices.delete_device_certificate(device_certificate) do
      send_resp(conn, :no_content, "")
    end
  end
end

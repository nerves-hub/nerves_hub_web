defmodule NervesHubAPIWeb.DeviceCertificateController do
  use NervesHubAPIWeb, :controller

  alias NervesHubWebCore.{Devices, Certificate, CertificateAuthority}

  action_fallback(NervesHubAPIWeb.FallbackController)

  plug(:validate_role, [org: :delete] when action in [:delete])
  plug(:validate_role, [org: :write] when action in [:sign, :create])
  plug(:validate_role, [org: :read] when action in [:index, :show])

  def index(%{assigns: %{org: org}} = conn, %{"device_identifier" => identifier}) do
    with {:ok, device} <- Devices.get_device_by_identifier(org, identifier) do
      device_certificates = Devices.get_device_certificates(device)
      render(conn, "index.json", device_certificates: device_certificates)
    end
  end

  def show(%{assigns: %{device: device}} = conn, %{"serial" => serial}) do
    with {:ok, device_certificate} <-
           Devices.get_device_certificate_by_device_and_serial(device, serial) do
      render(conn, "show.json", device_certificate: device_certificate)
    end
  end

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
        Routes.device_certificate_path(
          conn,
          :show,
          org.name,
          product.name,
          device.identifier,
          device_certificate.serial
        )
      )
      |> render("show.json", device_certificate: device_certificate)
    else
      {:error, :not_found} -> {:error, "error decoding certificate"}
      e -> e
    end
  end

  def sign(%{assigns: %{device: device}} = conn, %{"csr" => csr}) do
    with {:ok, %{"cert" => cert_pem}} <- CertificateAuthority.sign_device_csr(csr),
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
           der: Certificate.to_der(cert)
         },
         {:ok, _db_cert} <- Devices.create_device_certificate(device, params) do
      render(conn, "cert.json", cert: cert_pem, device_certificate: cert_pem)
    end
  end

  def delete(%{assigns: %{device: device}} = conn, %{"serial" => serial}) do
    with {:ok, device_certificate} <-
           Devices.get_device_certificate_by_device_and_serial(device, serial),
         {:ok, _device_certificate} <- Devices.delete_device_certificate(device_certificate) do
      send_resp(conn, :no_content, "")
    end
  end
end

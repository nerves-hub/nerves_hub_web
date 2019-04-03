defmodule NervesHubAPIWeb.DeviceCertificateController do
  use NervesHubAPIWeb, :controller

  alias NervesHubWebCore.{Devices, Certificate, CertificateAuthority}

  action_fallback(NervesHubAPIWeb.FallbackController)

  plug(:validate_role, [org: :write] when action in [:sign])
  plug(:validate_role, [org: :read] when action in [:index])

  def index(%{assigns: %{org: org}} = conn, %{"device_identifier" => identifier}) do
    with {:ok, device} <- Devices.get_device_by_identifier(org, identifier) do
      device_certificates = Devices.get_device_certificates(device)
      render(conn, "index.json", device_certificates: device_certificates)
    end
  end

  def sign(%{assigns: %{org: org}} = conn, %{"csr" => csr, "device_identifier" => identifier}) do
    with {:ok, device} <- Devices.get_device_by_identifier(org, identifier),
         {:ok, %{"cert" => cert_pem}} <- CertificateAuthority.sign_device_csr(csr),
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
           not_after: not_after
         },
         {:ok, _db_cert} <- Devices.create_device_certificate(device, params) do
      render(conn, "cert.json", cert: cert_pem, device_certificate: cert_pem)
    end
  end
end

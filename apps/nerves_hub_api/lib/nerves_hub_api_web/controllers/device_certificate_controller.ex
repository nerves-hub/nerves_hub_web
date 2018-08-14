defmodule NervesHubAPIWeb.DeviceCertificateController do
  use NervesHubAPIWeb, :controller

  alias NervesHubCore.{Devices, Certificate, CertificateAuthority}

  action_fallback(NervesHubAPIWeb.FallbackController)

  def index(%{assigns: %{org: org}} = conn, %{"identifier" => identifier}) do
    with {:ok, device} <- Devices.get_device_by_identifier(org, identifier) do
      device_certificates = Devices.get_device_certificates(device)
      render(conn, "index.json", device_certificates: device_certificates)
    end
  end

  def sign(%{assigns: %{org: org}} = conn, %{"csr" => csr, "identifier" => identifier}) do
    with {:ok, device} <- Devices.get_device_by_identifier(org, identifier),
         {:ok, %{"cert" => cert}} <- CertificateAuthority.sign_device_csr(csr),
         {:ok, serial} <- Certificate.get_serial_number(cert),
         {not_before, not_after} <- Certificate.get_validity(cert),
         params <- %{serial: serial, not_before: not_before, not_after: not_after},
         {:ok, _db_cert} <- Devices.create_device_certificate(device, params) do
      render(conn, "cert.json", cert: cert, device_certificate: cert)
    end
  end
end

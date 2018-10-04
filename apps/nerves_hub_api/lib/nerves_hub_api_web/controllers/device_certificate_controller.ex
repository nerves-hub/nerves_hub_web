defmodule NervesHubAPIWeb.DeviceCertificateController do
  use NervesHubAPIWeb, :controller

  alias NervesHubCore.{Devices, Certificate, CertificateAuthority}

  action_fallback(NervesHubAPIWeb.FallbackController)

  def index(%{assigns: %{org: org}} = conn, %{"device_identifier" => identifier}) do
    with {:ok, device} <- Devices.get_device_by_identifier(org, identifier) do
      device_certificates = Devices.get_device_certificates(device)
      render(conn, "index.json", device_certificates: device_certificates)
    end
  end

  def sign(%{assigns: %{org: org}} = conn, %{"csr" => csr, "device_identifier" => identifier}) do
    with {:ok, device} <- Devices.get_device_by_identifier(org, identifier),
         {:ok, %{"cert" => cert}} <- CertificateAuthority.sign_device_csr(csr),
         {:ok, serial} <- Certificate.get_serial_number(cert),
         {:ok, authority_key_id} <- Certificate.get_authority_key_id(cert),
         authority_key_id <- Certificate.binary_to_hex_string(authority_key_id),
         {:ok, {not_before, not_after}} <- Certificate.get_validity(cert),
         params <- %{
           serial: serial,
           authority_key_id: authority_key_id,
           not_before: not_before,
           not_after: not_after
         },
         {:ok, _db_cert} <- Devices.create_device_certificate(device, params) do
      render(conn, "cert.json", cert: cert, device_certificate: cert)
    end
  end
end

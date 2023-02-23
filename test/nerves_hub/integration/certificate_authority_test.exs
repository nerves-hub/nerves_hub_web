defmodule NervesHub.Integration.CertificateAuthorityTest do
  use ExUnit.Case, async: true

  @tag :ca_integration
  test "Can generate new device certificates" do
    serial = "device-1234"
    {:ok, resp} = NervesHub.CertificateAuthority.create_device_certificate(serial)
    assert %{"cert" => cert, "key" => _key} = resp
    cert = X509.Certificate.from_pem!(cert)
    assert ^serial = NervesHub.Certificate.get_common_name(cert)
  end
end

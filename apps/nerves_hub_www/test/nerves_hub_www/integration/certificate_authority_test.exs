defmodule NervesHubWWW.Integration.CertificateAuthorityTest do
  use ExUnit.Case, async: true

  @tag :ca_integration
  test "Can generate new device certificates" do
    serial = "device-1234"
    {:ok, resp} = NervesHubCore.CertificateAuthority.create_device_certificate(serial)
    assert %{"cert" => cert, "key" => key} = resp
    cert = X509.Certificate.from_pem!(cert)
    assert ^serial = NervesHubCore.Certificate.get_common_name(cert)
  end
end

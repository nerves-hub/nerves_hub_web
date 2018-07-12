defmodule NervesHub.Integration.CertificateAuthorityTest do
  use ExUnit.Case, async: false

  @tag :ca_integration
  test "Can generate new device certificates" do
    serial = "12345"
    {:ok, resp} = NervesHub.CertificateAuthority.create_device_certificate(serial)
    %{"certificate" => cert} = resp
    assert {:ok, ^serial} = NervesHubCore.Certificate.get_device_serial(cert)
  end
end

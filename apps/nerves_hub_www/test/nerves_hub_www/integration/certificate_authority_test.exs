defmodule NervesHubWWW.Integration.CertificateAuthorityTest do
  use ExUnit.Case, async: false

  @tag :ca_integration
  test "Can generate new device certificates" do
    serial = "12345"
    {:ok, resp} = NervesHubCore.CertificateAuthority.create_device_certificate(serial)
    %{"certificate" => cert} = resp
    assert {:ok, ^serial} = NervesHubCore.Certificate.get_common_name(cert)
  end
end

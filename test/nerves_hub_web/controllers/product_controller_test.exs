defmodule NervesHubWeb.ProductControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceCertificate
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  setup %{user: user, org: org} do
    [product: Fixtures.product_fixture(user, org)]
  end

  test "download device list csv", %{
    conn: conn,
    org: org,
    product: product,
    user: user,
    tmp_dir: tmp_dir
  } do
    Repo.delete_all(Device)
    Repo.delete_all(DeviceCertificate)

    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    %{db_cert: db_cert} = Fixtures.device_certificate_fixture(device)

    ##
    # Need to create a second certificate without a DER saved to test JSON
    # TODO: Remove when DERs are saved
    %{cert: ca1, key: ca1_key} = Fixtures.ca_certificate_fixture(org)

    otp_cert =
      X509.PrivateKey.new_ec(:secp256r1)
      |> X509.PublicKey.derive()
      |> X509.Certificate.new("CN=#{device.identifier}", ca1, ca1_key)

    %{db_cert: db_cert_no_der} =
      Fixtures.device_certificate_fixture_without_der(device, otp_cert)

    conn = get(conn, ~p"/org/#{org}/#{product}/devices/export")

    [str] = Plug.Conn.get_resp_header(conn, "content-disposition")

    assert str =~ "attachment; filename"

    [[id, desc, tags, product_name, org_name, cert_io] | _] =
      NimbleCSV.RFC4180.parse_string(conn.resp_body)

    assert id == device.identifier
    assert desc == device.description || ""
    assert String.split(tags, ",") == device.tags
    assert product_name == product.name
    assert org_name == org.name

    String.split(cert_io, "\n\n")
    |> Enum.each(fn
      "{" <> _ = cert_json ->
        # TODO: Remove testing JSON when DERs saved
        parsed_cert = Jason.decode!(cert_json)

        assert parsed_cert["serial"] == db_cert_no_der.serial
        assert parsed_cert["not_before"] == DateTime.to_iso8601(db_cert_no_der.not_before)
        assert parsed_cert["not_after"] == DateTime.to_iso8601(db_cert_no_der.not_after)
        assert Base.decode16!(parsed_cert["aki"]) == db_cert_no_der.aki
        assert Base.decode16!(parsed_cert["ski"]) == db_cert_no_der.ski

      "---" <> _ = cert_pem ->
        assert X509.Certificate.from_pem!(cert_pem) == X509.Certificate.from_der!(db_cert.der)

      _ ->
        :ignore
    end)
  end
end

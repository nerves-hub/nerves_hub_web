defmodule NervesHub.Devices.DeviceCertificateTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Certificate
  alias NervesHub.Devices.DeviceCertificate
  alias NervesHub.Fixtures

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    %{user: user, org: org, device: device}
  end

  test "changeset/2 with from_json: true skips DER requirement", %{org: org, device: device} do
    params = %{
      org_id: org.id,
      device_id: device.id,
      serial: "test-serial-no-der",
      aki: <<1, 2, 3>>,
      not_before: DateTime.utc_now(),
      not_after: DateTime.utc_now() |> DateTime.add(365 * 24 * 3600),
      from_json: true
    }

    changeset = DeviceCertificate.changeset(%DeviceCertificate{}, params)
    # No DER required — should not have a DER error (but may have other errors)
    refute Keyword.has_key?(changeset.errors, :der)
  end

  test "changeset/2 with AKI matching a CA from another org adds org error", %{
    org: org,
    device: device
  } do
    # Create a CA cert in a different org
    user2 = Fixtures.user_fixture()
    org2 = Fixtures.org_fixture(user2)
    %{db_cert: ca_cert} = Fixtures.ca_certificate_fixture(org2)

    # Try to create a device cert in org1 using AKI that points to org2's CA
    params = %{
      org_id: org.id,
      device_id: device.id,
      serial: "conflict-serial",
      aki: ca_cert.ski,
      not_before: DateTime.utc_now(),
      not_after: DateTime.utc_now() |> DateTime.add(365 * 24 * 3600),
      from_json: true
    }

    changeset = DeviceCertificate.changeset(%DeviceCertificate{}, params)
    assert {:org, {"Signer CA registered with another org", []}} in changeset.errors
  end

  test "changeset/2 with AKI matching CA from same org is valid (no org error)", %{
    org: org,
    device: device
  } do
    %{db_cert: ca_cert} = Fixtures.ca_certificate_fixture(org)

    params = %{
      org_id: org.id,
      device_id: device.id,
      serial: "same-org-serial",
      aki: ca_cert.ski,
      not_before: DateTime.utc_now(),
      not_after: DateTime.utc_now() |> DateTime.add(365 * 24 * 3600),
      from_json: true
    }

    changeset = DeviceCertificate.changeset(%DeviceCertificate{}, params)
    refute Keyword.has_key?(changeset.errors, :org)
  end

  test "changeset/2 duplicate public_key_fingerprint for different device adds error", %{
    tmp_dir: tmp_dir,
    org: org,
    device: device
  } do
    # Create another device in same org/product
    user2 = Fixtures.user_fixture()
    org2 = Fixtures.org_fixture(user2)
    product2 = Fixtures.product_fixture(user2, org2)
    org_key2 = Fixtures.org_key_fixture(org2, user2, tmp_dir)
    firmware2 = Fixtures.firmware_fixture(org_key2, product2, %{dir: tmp_dir})
    device2 = Fixtures.device_fixture(org2, product2, firmware2)

    # Create a cert for device1
    %{db_cert: existing_cert, cert: existing_x509_cert} = Fixtures.device_certificate_fixture(device)

    # Try to create a cert for device2 using the same public key (same DER)
    der = Certificate.to_der(existing_x509_cert)
    serial2 = "different-serial-same-pk"

    params = %{
      org_id: org2.id,
      device_id: device2.id,
      serial: serial2,
      aki: Certificate.get_aki(existing_x509_cert),
      not_before: DateTime.utc_now(),
      not_after: DateTime.utc_now() |> DateTime.add(365 * 24 * 3600),
      der: der
    }

    changeset = DeviceCertificate.changeset(%DeviceCertificate{}, params)
    assert {:public_key_fingerprint, {"public key already associated with another device", []}} in changeset.errors
  end
end

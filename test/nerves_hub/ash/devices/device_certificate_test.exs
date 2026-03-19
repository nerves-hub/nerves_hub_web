defmodule NervesHub.Ash.Devices.DeviceCertificateTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Ash.Devices.DeviceCertificate
  alias NervesHub.Fixtures

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)
    %{db_cert: db_cert} = Fixtures.device_certificate_fixture(device)

    %{device: device, db_cert: db_cert}
  end

  describe "read" do
    test "list_by_device returns certs", %{device: device, db_cert: db_cert} do
      certs = DeviceCertificate.list_by_device!(device.id)
      assert Enum.any?(certs, &(&1.id == db_cert.id))
    end

    test "get_by_device_and_serial returns cert", %{device: device, db_cert: db_cert} do
      found = DeviceCertificate.get_by_device_and_serial!(device.id, db_cert.serial)
      assert found.id == db_cert.id
    end
  end

  describe "get_by_fingerprint" do
    test "returns cert by fingerprint", %{db_cert: db_cert} do
      found = DeviceCertificate.get_by_fingerprint!(db_cert.fingerprint)
      assert found.id == db_cert.id
    end
  end

  describe "get_by_public_key_fingerprint" do
    test "returns cert by public key fingerprint", %{db_cert: db_cert} do
      found = DeviceCertificate.get_by_public_key_fingerprint!(db_cert.public_key_fingerprint)
      assert found.id == db_cert.id
    end
  end

  describe "update" do
    test "updates last_used", %{db_cert: db_cert} do
      ash_cert = DeviceCertificate.get!(db_cert.id)
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      updated = DeviceCertificate.update!(ash_cert, %{last_used: now})
      assert updated.last_used == now
    end
  end

  describe "destroy" do
    test "deletes device certificate", %{db_cert: db_cert} do
      ash_cert = DeviceCertificate.get!(db_cert.id)
      assert :ok = DeviceCertificate.destroy!(ash_cert)
    end
  end
end

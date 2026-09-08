defmodule NervesHub.Devices.CACertificatesTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Devices
  alias NervesHub.Devices.CACertificates
  alias NervesHub.Fixtures

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)

    %{user: user, org: org, product: product, firmware: firmware, org_key: org_key}
  end

  describe "device_counts_by_ski/1" do
    test "counts the devices signed by each CA", %{org: org, product: product, firmware: firmware} do
      ca_one = Fixtures.ca_certificate_fixture(org)
      ca_two = Fixtures.ca_certificate_fixture(org)

      for _ <- 1..2 do
        device = Fixtures.device_fixture(org, product, firmware)
        Fixtures.device_certificate_fixture_for_ca(device, ca_one)
      end

      device = Fixtures.device_fixture(org, product, firmware)
      Fixtures.device_certificate_fixture_for_ca(device, ca_two)

      counts = CACertificates.device_counts_by_ski(org)

      assert counts[ca_one.db_cert.ski] == 2
      assert counts[ca_two.db_cert.ski] == 1
    end

    test "counts a device with several certificates from the same CA once", %{
      org: org,
      product: product,
      firmware: firmware
    } do
      ca = Fixtures.ca_certificate_fixture(org)
      device = Fixtures.device_fixture(org, product, firmware)

      Fixtures.device_certificate_fixture_for_ca(device, ca)
      Fixtures.device_certificate_fixture_for_ca(device, ca)

      assert CACertificates.device_counts_by_ski(org)[ca.db_cert.ski] == 1
    end

    test "leaves out soft deleted devices", %{org: org, product: product, firmware: firmware} do
      ca = Fixtures.ca_certificate_fixture(org)
      device = Fixtures.device_fixture(org, product, firmware)
      Fixtures.device_certificate_fixture_for_ca(device, ca)

      {:ok, _device} = Devices.delete_device(device)

      refute Map.has_key?(CACertificates.device_counts_by_ski(org), ca.db_cert.ski)
    end

    test "has no entry for a CA which signed nothing", %{org: org} do
      ca = Fixtures.ca_certificate_fixture(org)

      assert CACertificates.device_counts_by_ski(org) == %{}
      refute Map.has_key?(CACertificates.device_counts_by_ski(org), ca.db_cert.ski)
    end

    test "does not count another org's devices", %{org: org, product: product, firmware: firmware} do
      ca = Fixtures.ca_certificate_fixture(org)
      device = Fixtures.device_fixture(org, product, firmware)
      Fixtures.device_certificate_fixture_for_ca(device, ca)

      other_user = Fixtures.user_fixture()
      other_org = Fixtures.org_fixture(other_user)

      assert CACertificates.device_counts_by_ski(other_org) == %{}
    end
  end

  describe "device_counts_by_product/1" do
    test "breaks the count down by product, ordered by name", %{
      user: user,
      org: org,
      product: product,
      firmware: firmware,
      org_key: org_key
    } do
      ca = Fixtures.ca_certificate_fixture(org)

      other_product = Fixtures.product_fixture(user, org, %{name: "AAA other product"})
      other_firmware = Fixtures.firmware_fixture(org_key, other_product)

      for _ <- 1..2 do
        device = Fixtures.device_fixture(org, product, firmware)
        Fixtures.device_certificate_fixture_for_ca(device, ca)
      end

      device = Fixtures.device_fixture(org, other_product, other_firmware)
      Fixtures.device_certificate_fixture_for_ca(device, ca)

      assert [
               %{product: %{id: other_id}, device_count: 1},
               %{product: %{id: id}, device_count: 2}
             ] = CACertificates.device_counts_by_product(ca.db_cert)

      assert other_id == other_product.id
      assert id == product.id
    end

    test "is empty for a CA which signed nothing", %{org: org} do
      ca = Fixtures.ca_certificate_fixture(org)

      assert CACertificates.device_counts_by_product(ca.db_cert) == []
    end

    test "leaves out soft deleted devices", %{org: org, product: product, firmware: firmware} do
      ca = Fixtures.ca_certificate_fixture(org)
      device = Fixtures.device_fixture(org, product, firmware)
      Fixtures.device_certificate_fixture_for_ca(device, ca)

      {:ok, _device} = Devices.delete_device(device)

      assert CACertificates.device_counts_by_product(ca.db_cert) == []
    end
  end

  describe "signer_cas_for_product/1" do
    test "only returns CAs which signed a certificate held by a device in the product", %{
      org: org,
      product: product,
      firmware: firmware
    } do
      used = Fixtures.ca_certificate_fixture(org)
      _unused = Fixtures.ca_certificate_fixture(org)

      device = Fixtures.device_fixture(org, product, firmware)
      Fixtures.device_certificate_fixture_for_ca(device, used)

      assert [ca] = CACertificates.signer_cas_for_product(product.id)
      assert ca.id == used.db_cert.id
    end

    test "returns each CA once no matter how many devices use it", %{
      org: org,
      product: product,
      firmware: firmware
    } do
      ca = Fixtures.ca_certificate_fixture(org)

      for _ <- 1..3 do
        device = Fixtures.device_fixture(org, product, firmware)
        Fixtures.device_certificate_fixture_for_ca(device, ca)
      end

      assert [_ca] = CACertificates.signer_cas_for_product(product.id)
    end

    test "does not return CAs used only by another product", %{
      user: user,
      org: org,
      product: product,
      firmware: firmware,
      org_key: org_key
    } do
      ca = Fixtures.ca_certificate_fixture(org)
      device = Fixtures.device_fixture(org, product, firmware)
      Fixtures.device_certificate_fixture_for_ca(device, ca)

      other_product = Fixtures.product_fixture(user, org, %{name: "other product"})
      _other_firmware = Fixtures.firmware_fixture(org_key, other_product)

      assert CACertificates.signer_cas_for_product(other_product.id) == []
    end
  end

  describe "by_ski/2" do
    test "returns the org's CAs keyed by SKI", %{org: org} do
      ca_one = Fixtures.ca_certificate_fixture(org)
      ca_two = Fixtures.ca_certificate_fixture(org)

      found = CACertificates.by_ski(org, [ca_one.db_cert.ski, ca_two.db_cert.ski])

      assert found[ca_one.db_cert.ski].id == ca_one.db_cert.id
      assert found[ca_two.db_cert.ski].id == ca_two.db_cert.id
    end

    test "ignores nil SKIs and unknown ones", %{org: org} do
      ca = Fixtures.ca_certificate_fixture(org)

      assert %{} == CACertificates.by_ski(org, [nil])
      assert map_size(CACertificates.by_ski(org, [nil, ca.db_cert.ski, "nope"])) == 1
    end

    test "does not return another org's CA", %{org: org} do
      other_user = Fixtures.user_fixture()
      other_org = Fixtures.org_fixture(other_user)
      other_ca = Fixtures.ca_certificate_fixture(other_org)

      assert CACertificates.by_ski(org, [other_ca.db_cert.ski]) == %{}
    end
  end
end

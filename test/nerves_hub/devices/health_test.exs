defmodule NervesHub.Devices.HealthTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Devices
  alias NervesHub.Devices.Health
  alias NervesHub.Fixtures

  @moduletag :tmp_dir

  describe "status_counts_by_product/1" do
    setup %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      product = Fixtures.product_fixture(user, org)
      other_product = Fixtures.product_fixture(user, org)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      other_firmware = Fixtures.firmware_fixture(org_key, other_product, %{dir: tmp_dir})

      %{org: org, product: product, firmware: firmware, other_product: other_product, other_firmware: other_firmware}
    end

    defp device_with_health(org, product, firmware, status) do
      device = Fixtures.device_fixture(org, product, firmware)
      {:ok, _} = Health.save_device_health(%{device_id: device.id, status: status})
      device
    end

    test "counts each product's healthy, warning and unhealthy devices", context do
      %{org: org, product: product, firmware: firmware} = context
      %{other_product: other_product, other_firmware: other_firmware} = context

      device_with_health(org, product, firmware, :healthy)
      device_with_health(org, product, firmware, :healthy)
      device_with_health(org, product, firmware, :warning)
      device_with_health(org, product, firmware, :unhealthy)
      device_with_health(org, other_product, other_firmware, :unhealthy)

      assert Health.status_counts_by_product([product.id, other_product.id]) == %{
               product.id => %{healthy: 2, warning: 1, unhealthy: 1},
               other_product.id => %{healthy: 0, warning: 0, unhealthy: 1}
             }
    end

    # A device that has never reported is not healthy, so a product of them
    # must not read as healthy either.
    test "leaves out devices with no verdict and products with no reports", context do
      %{org: org, product: product, firmware: firmware, other_product: other_product} = context

      _never_reported = Fixtures.device_fixture(org, product, firmware)
      device_with_health(org, product, firmware, :unknown)

      assert Health.status_counts_by_product([product.id, other_product.id]) == %{}
    end

    test "leaves out deleted devices", %{org: org, product: product, firmware: firmware} do
      device = device_with_health(org, product, firmware, :unhealthy)
      {:ok, _} = Devices.delete_device(device)

      assert Health.status_counts_by_product([product.id]) == %{}
    end

    test "is empty for no products" do
      assert Health.status_counts_by_product([]) == %{}
    end
  end
end

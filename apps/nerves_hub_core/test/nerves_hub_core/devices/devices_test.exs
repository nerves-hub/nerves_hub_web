defmodule NervesHubCore.DevicesTest do
  use NervesHubCore.DataCase

  alias NervesHub.Fixtures
  alias NervesHubCore.Devices
  alias Ecto.Changeset

  setup do
    tenant = Fixtures.tenant_fixture()
    product = Fixtures.product_fixture(tenant)
    tenant_key = Fixtures.tenant_key_fixture(tenant)
    firmware = Fixtures.firmware_fixture(tenant, tenant_key, product)
    deployment = Fixtures.deployment_fixture(tenant, firmware, product)
    device = Fixtures.device_fixture(tenant, firmware, deployment, product)

    {:ok,
     %{
       tenant: tenant,
       firmware: firmware,
       device: device,
       deployment: deployment,
       product: product
     }}
  end

  test 'create_device with valid parameters', %{
    tenant: tenant,
    firmware: firmware,
    product: product
  } do
    params = %{
      tenant_id: tenant.id,
      product_id: product.id,
      identifier: "valid identifier",
      architecture: firmware.architecture,
      platform: firmware.platform
    }

    {:ok, %Devices.Device{} = device} = Devices.create_device(params)

    for key <- Map.keys(params) do
      assert Map.get(device, key) == Map.get(params, key)
    end
  end

  test 'create_device with invalid parameters', %{firmware: firmware} do
    params = %{
      identifier: "valid identifier",
      architecture: firmware.architecture,
      platform: firmware.platform
    }

    assert {:error, %Changeset{}} = Devices.create_device(params)
  end

  test 'get_device_by_identifier with existing device', %{device: target_device} do
    assert {:ok, result} = Devices.get_device_by_identifier(target_device.identifier)

    for key <- [:tenant_id, :deployment_id, :device_identifier] do
      assert Map.get(target_device, key) == Map.get(result, key)
    end
  end

  test 'get_device_by_identifier without existing device' do
    assert {:error, :not_found} = Devices.get_device_by_identifier("non existing identifier")
  end
end

defmodule NervesHub.DevicesTest do
  use NervesHub.DataCase

  alias NervesHub.Fixtures
  alias NervesHub.Devices
  alias Ecto.Changeset

  setup do
    tenant = Fixtures.tenant_fixture()
    firmware = Fixtures.firmware_fixture(tenant)
    deployment = Fixtures.deployment_fixture(tenant, firmware)
    device = Fixtures.device_fixture(tenant, firmware, deployment)

    {:ok, %{tenant: tenant, firmware: firmware, deployment: deployment, device: device}}
  end

  test 'create_device with valid parameters', %{tenant: tenant, firmware: firmware} do
    params = %{
      tenant_id: tenant.id,
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

  test 'create_device_with_tenant with valid parameters', %{tenant: tenant, firmware: firmware} do
    params = %{
      identifier: "valid identifier",
      architecture: firmware.architecture,
      platform: firmware.platform
    }

    {:ok, %Devices.Device{} = device} = Devices.create_device_with_tenant(tenant, params)
    assert device.tenant_id == tenant.id

    for key <- Map.keys(params) do
      assert Map.get(device, key) == Map.get(params, key)
    end
  end

  test 'create_device_with_tenant with invalid parameters', %{tenant: tenant, firmware: firmware} do
    params = %{
      identifier: 1,
      architecture: firmware.architecture,
      platform: firmware.platform
    }

    assert {:error, %Changeset{}} = Devices.create_device_with_tenant(tenant, params)
  end

  test 'get_device_by_identifier with existing device', %{device: target_device} do
    assert {:ok, ^target_device} = Devices.get_device_by_identifier(target_device.identifier)
  end

  test 'get_device_by_identifier without existing device' do
    assert {:error, :not_found} = Devices.get_device_by_identifier("non existing identifier")
  end
end

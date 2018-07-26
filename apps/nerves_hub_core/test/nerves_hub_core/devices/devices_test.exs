defmodule NervesHubCore.DevicesTest do
  use NervesHubCore.DataCase

  alias NervesHubWeb.Fixtures
  alias NervesHubCore.Devices
  alias NervesHubCore.Deployments
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
       tenant_key: tenant_key,
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
      last_known_firmware_id: firmware.id,
      identifier: "valid identifier"
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

  test "get_eligible_deployments returns proper deployments", %{
    tenant: tenant,
    tenant_key: tenant_key,
    firmware: firmware,
    deployment: old_deployment,
    product: product
  } do
    device =
      Fixtures.device_fixture(tenant, firmware, old_deployment, product, %{
        identifier: "new identifier"
      })

    new_firmware = Fixtures.firmware_fixture(tenant, tenant_key, product, %{version: "1.0.1"})

    params = %{
      firmware_id: new_firmware.id,
      name: "my deployment",
      conditions: %{
        "version" => "< 1.0.1",
        "tags" => ["beta", "beta-edge"]
      },
      is_active: false
    }

    {:ok, deployment} =
      Deployments.create_deployment(params)
      |> elem(1)
      |> Deployments.update_deployment(%{is_active: true})

    {:ok, device_with_firmware} = Devices.get_device(tenant, device.id)

    [%Deployments.Deployment{id: dep_id} | _] =
      Devices.get_eligible_deployments(device_with_firmware)

    assert dep_id == deployment.id
  end

  test "get_eligible_deployment does not return incorrect devices", %{
    tenant: tenant,
    tenant_key: tenant_key,
    firmware: firmware,
    deployment: old_deployment,
    product: product
  } do
    incorrect_params = [
      {%{version: "1.0.0"}, %{identifier: "foo"}},
      {%{}, %{identifier: "foobar", tags: ["beta"]}},
      {%{}, %{identifier: "foobarbaz", architecture: "foo"}},
      {%{}, %{identifier: "foobarbazbang", platform: "foo"}}
    ]

    for {f_params, d_params} <- incorrect_params do
      device = Fixtures.device_fixture(tenant, firmware, old_deployment, product, d_params)
      new_firmware = Fixtures.firmware_fixture(tenant, tenant_key, product, f_params)

      params = %{
        firmware_id: new_firmware.id,
        name: "my deployment",
        conditions: %{
          "version" => "< 1.0.0",
          "tags" => ["beta", "beta-edge"]
        },
        is_active: false
      }

      {:ok, deployment} =
        Deployments.create_deployment(params)
        |> elem(1)
        |> Deployments.update_deployment(%{is_active: true})

      {:ok, device_with_firmware} = Devices.get_device(tenant, device.id)

      assert [] == Devices.get_eligible_deployments(device_with_firmware)
    end
  end
end

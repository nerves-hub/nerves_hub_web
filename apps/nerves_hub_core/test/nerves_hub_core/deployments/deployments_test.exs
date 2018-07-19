defmodule NervesHubCore.DeploymentsTest do
  use NervesHubCore.DataCase

  alias NervesHub.Fixtures
  alias NervesHubCore.Deployments
  alias NervesHubCore.Devices
  alias Ecto.Changeset

  setup do
    tenant = Fixtures.tenant_fixture()
    product = Fixtures.product_fixture(tenant)
    tenant_key = Fixtures.tenant_key_fixture(tenant)
    firmware = Fixtures.firmware_fixture(tenant, tenant_key, product)
    deployment = Fixtures.deployment_fixture(tenant, firmware, product)

    {:ok,
     %{
       tenant: tenant,
       tenant_key: tenant_key,
       firmware: firmware,
       deployment: deployment,
       product: product
     }}
  end

  test 'create_deployment with valid parameters', %{
    firmware: firmware,
    product: product
  } do
    params = %{
      firmware_id: firmware.id,
      product_id: product.id,
      name: "my deployment",
      conditions: %{
        "version" => "< 1.0.0",
        "tags" => ["beta", "beta-edge"]
      },
      is_active: true
    }

    {:ok, %Deployments.Deployment{} = deployment} = Deployments.create_deployment(params)

    for key <- Map.keys(params) do
      assert Map.get(deployment, key) == Map.get(params, key)
    end
  end

  test 'create_deployment updates correct devices', %{
    tenant: tenant,
    tenant_key: tenant_key,
    deployment: old_deployment,
    product: product
  } do
    firmware = Fixtures.firmware_fixture(tenant, tenant_key, product, %{version: "1.0.0"})
    device = Fixtures.device_fixture(tenant, firmware, old_deployment, product)

    params = %{
      firmware_id: firmware.id,
      product_id: product.id,
      name: "my deployment",
      conditions: %{
        "version" => "< 1.0.0",
        "tags" => ["beta", "beta-edge"]
      },
      is_active: true
    }

    {:ok, %Deployments.Deployment{} = deployment} = Deployments.create_deployment(params)

    {:ok, updated_device} = Devices.get_device(tenant, device.id)
    refute updated_device.target_deployment_id == deployment.id
  end

  test 'create_deployment does not update incorrect devices', %{
    tenant: tenant,
    tenant_key: tenant_key,
    deployment: old_deployment,
    product: product
  } do
    incorrect_params = [
      {%{version: "1.0.0"}, %{}},
      {%{}, %{identifier: "new identifier", tags: ["beta"]}},
      {%{}, %{identifier: "newnew identifier", architecture: "foo"}},
      {%{}, %{identifier: "newnewnew identifier", platform: "foo"}}
    ]

    for {f_params, d_params} <- incorrect_params do
      firmware = Fixtures.firmware_fixture(tenant, tenant_key, product, f_params)
      device = Fixtures.device_fixture(tenant, firmware, old_deployment, product, d_params)

      params = %{
        firmware_id: firmware.id,
        product_id: product.id,
        name: "my deployment",
        conditions: %{
          "version" => "<= 1.0.0",
          "tags" => ["beta", "beta-edge"]
        },
        is_active: true
      }

      {:ok, %Deployments.Deployment{} = deployment} = Deployments.create_deployment(params)

      {:ok, updated_device} = Devices.get_device(tenant, device.id)
      assert updated_device.target_deployment_id == deployment.id
    end
  end

  test 'create_deployment with invalid parameters' do
    params = %{
      name: "my deployment",
      conditions: %{
        "version" => "< 1.0.0",
        "tags" => ["beta", "beta-edge"]
      },
      is_active: true
    }

    assert {:error, %Changeset{}} = Deployments.create_deployment(params)
  end
end

defmodule NervesHubCore.DeploymentsTest do
  use NervesHubCore.DataCase

  alias NervesHubWWW.Fixtures
  alias NervesHubCore.Deployments
  alias Ecto.Changeset

  setup do
    tenant = Fixtures.tenant_fixture()
    product = Fixtures.product_fixture(tenant)
    tenant_key = Fixtures.tenant_key_fixture(tenant)
    firmware = Fixtures.firmware_fixture(tenant, tenant_key, product)
    deployment = Fixtures.deployment_fixture(tenant, firmware, product)

    {:ok, %{tenant: tenant, firmware: firmware, deployment: deployment, product: product}}
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

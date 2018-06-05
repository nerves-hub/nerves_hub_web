defmodule NervesHub.DeploymentsTest do
  use NervesHub.DataCase

  alias NervesHub.Fixtures
  alias NervesHub.Deployments
  alias Ecto.Changeset

  setup do
    tenant = Fixtures.tenant_fixture()
    firmware = Fixtures.firmware_fixture(tenant)
    deployment = Fixtures.deployment_fixture(tenant, firmware)

    {:ok, %{tenant: tenant, firmware: firmware, deployment: deployment}}
  end

  test 'create_deployment with valid parameters', %{tenant: tenant, firmware: firmware} do
    params = %{
      tenant_id: tenant.id,
      firmware_id: firmware.id,
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

  test 'create_deployment_with_tenant with valid parameters', %{
    tenant: tenant,
    firmware: firmware
  } do
    params = %{
      firmware_id: firmware.id,
      name: "my deployment",
      conditions: %{
        "version" => "< 1.0.0",
        "tags" => ["beta", "beta-edge"]
      },
      is_active: true
    }

    {:ok, %Deployments.Deployment{} = deployment} =
      Deployments.create_deployment_with_tenant(tenant, params)

    for key <- [:firmware_id, :name, :conditions] do
      assert Map.get(deployment, key) == Map.get(params, key)
    end

    refute deployment.is_active
  end

  test 'create_deployment_with_tenant with invalid parameters', %{
    tenant: tenant
  } do
    params = %{
      name: "my deployment",
      conditions: %{
        "version" => "< 1.0.0",
        "tags" => ["beta", "beta-edge"]
      },
      is_active: true
    }

    {:error, %Changeset{}} = Deployments.create_deployment_with_tenant(tenant, params)
  end
end

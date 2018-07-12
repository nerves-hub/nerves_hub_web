defmodule NervesHubCore.Fixtures do
  alias NervesHubCore.{Accounts,Devices,Deployments,Firmwares}

  @tenant_params %{name: "Test Tenant"}
  @tenant_key_params %{
    name: "Test Key",
    key: File.read!("../../test/fixtures/firmware/fwup-key1.pub")
  }
  @firmware_params %{
    architecture: "arm",
    author: "test_author",
    description: "test_description",
    platform: "rpi0",
    product: "test_product",
    upload_metadata: %{"public_url" => "http://example.com"},
    version: "1.0.0",
    vcs_identifier: "test_vcs_identifier",
    misc: "test_misc",
    uuid: "00000000-0000-0000-0000-000000000000"
  }
  @deployment_params %{
    name: "Test Deployment",
    conditions: %{
      "version" => "< 1.0.0",
      "tags" => ["beta", "beta-edge"]
    },
    is_active: true
  }
  @device_params %{identifier: "device-1234"}

  def tenant_fixture(params \\ %{}) do
    {:ok, tenant} =
      params
      |> Enum.into(@tenant_params)
      |> Accounts.create_tenant()

    tenant
  end

  def tenant_key_fixture(%Accounts.Tenant{} = tenant, params \\ %{}) do
    {:ok, tenant_key} =
      %{tenant_id: tenant.id}
      |> Enum.into(params)
      |> Enum.into(@tenant_key_params)
      |> Accounts.create_tenant_key()

    tenant_key
  end

  def firmware_fixture(
        %Accounts.Tenant{} = tenant,
        %Accounts.TenantKey{} = tenant_key,
        params \\ %{}
      ) do
    {:ok, firmware} =
      %{tenant_id: tenant.id, tenant_key_id: tenant_key.id}
      |> Enum.into(params)
      |> Enum.into(@firmware_params)
      |> Firmwares.create_firmware()

    firmware
  end

  def deployment_fixture(
        %Accounts.Tenant{} = tenant,
        %Firmwares.Firmware{} = firmware,
        params \\ %{}
      ) do
    {:ok, deployment} =
      %{tenant_id: tenant.id, firmware_id: firmware.id}
      |> Enum.into(params)
      |> Enum.into(@deployment_params)
      |> Deployments.create_deployment()

    deployment
  end

  def device_fixture(
        %Accounts.Tenant{} = tenant,
        %Firmwares.Firmware{} = firmware,
        %Deployments.Deployment{} = deployment,
        params \\ %{}
      ) do
    {:ok, device} =
      %{
        tenant_id: tenant.id,
        target_deployment_id: deployment.id,
        current_firmware_id: firmware.id,
        architecture: firmware.architecture,
        platform: firmware.platform,
        tags: deployment.conditions["tags"]
      }
      |> Enum.into(params)
      |> Enum.into(@device_params)
      |> Devices.create_device()

    device
  end
end

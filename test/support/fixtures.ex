defmodule NervesHub.Fixtures do
  alias NervesHub.Accounts
  alias NervesHub.Devices
  alias NervesHub.Deployments
  alias NervesHub.Firmwares
  alias NervesHub.Products

  @tenant_params %{name: "Test Tenant"}
  @tenant_key_params %{
    name: "Test Key",
    key: File.read!("test/fixtures/firmware/fwup-key1.pub")
  }
  @firmware_params %{
    architecture: "arm",
    author: "test_author",
    description: "test_description",
    platform: "rpi0",
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
  @product_params %{name: "valid product"}
  @user_params %{
    name: "Testy McTesterson",
    tenant_name: "mctesterson.com",
    email: "testy@mctesterson.com",
    password: "test_password"
  }

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

  def user_fixture(%Accounts.Tenant{} = tenant, params \\ %{}) do
    user_params =
      params
      |> Enum.into(@user_params)

    {:ok, user} = Accounts.create_user(tenant, user_params)

    user
  end

  def product_fixture(a, params \\ %{})

  def product_fixture(%Accounts.Tenant{} = tenant, params) do
    {:ok, product} =
      %{tenant_id: tenant.id}
      |> Enum.into(params)
      |> Enum.into(@product_params)
      |> Products.create_product()

    product
  end

  def product_fixture(%{assigns: %{tenant: tenant}}, params) do
    {:ok, product} =
      %{tenant_id: tenant.id}
      |> Enum.into(params)
      |> Enum.into(@product_params)
      |> Products.create_product()

    product
  end

  def firmware_fixture(
        %Accounts.Tenant{} = tenant,
        %Accounts.TenantKey{} = tenant_key,
        %Products.Product{} = product,
        params \\ %{}
      ) do
    {:ok, firmware} =
      %{tenant_id: tenant.id, tenant_key_id: tenant_key.id, product_id: product.id}
      |> Enum.into(params)
      |> Enum.into(@firmware_params)
      |> Firmwares.create_firmware()

    firmware
  end

  def deployment_fixture(
        %Accounts.Tenant{} = tenant,
        %Firmwares.Firmware{} = firmware,
        %Products.Product{} = product,
        params \\ %{}
      ) do
    {:ok, deployment} =
      %{tenant_id: tenant.id, firmware_id: firmware.id, product_id: product.id}
      |> Enum.into(params)
      |> Enum.into(@deployment_params)
      |> Deployments.create_deployment()

    deployment
  end

  def device_fixture(
        %Accounts.Tenant{} = tenant,
        %Firmwares.Firmware{} = firmware,
        %Deployments.Deployment{} = deployment,
        %Products.Product{} = product,
        params \\ %{}
      ) do
    {:ok, device} =
      %{
        tenant_id: tenant.id,
        product_id: product.id,
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

  def very_fixture() do
    tenant = tenant_fixture(%{name: "Very"})
    user = user_fixture(tenant, %{name: "Jeff"})
    product = product_fixture(tenant, %{name: "Hop"})
    tenant_key = tenant_key_fixture(tenant)
    firmware = firmware_fixture(tenant, tenant_key, product)
    deployment = deployment_fixture(tenant, firmware, product)
    device = device_fixture(tenant, firmware, deployment, product)

    %{
      tenant: tenant,
      device: device,
      tenant_key: tenant_key,
      user: user,
      firmware: firmware,
      deployment: deployment,
      product: product
    }
  end

  def smartrent_fixture() do
    tenant = tenant_fixture(%{name: "Smart Rent"})
    product = product_fixture(tenant, %{name: "Smart Rent Thing"})
    tenant_key = tenant_key_fixture(tenant)
    firmware = firmware_fixture(tenant, tenant_key, product)
    deployment = deployment_fixture(tenant, firmware, product)

    device =
      device_fixture(tenant, firmware, deployment, product, %{identifier: "smartrent_1234"})

    %{
      tenant: tenant,
      tenant_key: tenant_key,
      device: device,
      firmware: firmware,
      deployment: deployment,
      product: product
    }
  end
end

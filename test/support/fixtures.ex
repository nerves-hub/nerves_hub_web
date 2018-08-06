defmodule NervesHubCore.Fixtures do
  alias NervesHubCore.{Firmwares, Accounts, Devices, Deployments, Products}

  @tenant_params %{name: "Test Tenant"}
  @tenant_key_params %{
    name: "Test Key"
  }
  @firmware_params %{
    architecture: "arm",
    author: "test_author",
    description: "test_description",
    platform: "rpi0",
    upload_metadata: %{"public_url" => "http://example.com"},
    version: "1.0.0",
    vcs_identifier: "test_vcs_identifier",
    misc: "test_misc"
  }
  @deployment_params %{
    name: "Test Deployment",
    conditions: %{
      "version" => "< 1.0.0",
      "tags" => ["beta", "beta-edge"]
    },
    is_active: false
  }
  @device_params %{identifier: "device-1234"}
  @product_params %{name: "valid product"}
  @user_params %{
    name: "Testy McTesterson",
    tenant_name: "mctesterson.com",
    email: "testy@mctesterson.com",
    password: "test_password"
  }
  @user_certificate_params %{
    description: "my test cert",
    serial: "158098897653878678601091983566405937658689714637"
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
      |> Enum.into(%{key: Ecto.UUID.generate()})
      |> Accounts.create_tenant_key()

    tenant_key
  end

  def user_fixture(%Accounts.Tenant{} = tenant, params \\ %{}) do
    user_params =
      params
      |> Enum.into(@user_params)

    {:ok, user} = Accounts.create_user(tenant, user_params)
    {:ok, _certificate} = Accounts.create_user_certificate(user, @user_certificate_params)
    user
  end

  def user_certificate_fixture(%Accounts.User{} = user, params \\ %{}) do
    cert_params =
      params
      |> Enum.into(@user_certificate_params)

    {:ok, certificate} = user |> Accounts.create_user_certificate(cert_params)
    certificate
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
        %Accounts.TenantKey{} = tenant_key,
        %Products.Product{} = product,
        params \\ %{}
      ) do
    {:ok, firmware} =
      %{tenant_key_id: tenant_key.id, product_id: product.id}
      |> Enum.into(params)
      |> Enum.into(@firmware_params)
      |> Enum.into(%{uuid: Ecto.UUID.generate()})
      |> Firmwares.create_firmware()

    firmware
  end

  def deployment_fixture(
        %Firmwares.Firmware{} = firmware,
        params \\ %{}
      ) do
    {:ok, deployment} =
      %{firmware_id: firmware.id}
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
        last_known_firmware_id: firmware.id,
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
    firmware = firmware_fixture(tenant_key, product)
    deployment = deployment_fixture(firmware)
    device = device_fixture(tenant, firmware, deployment)

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
    firmware = firmware_fixture(tenant_key, product)
    deployment = deployment_fixture(firmware)

    device = device_fixture(tenant, firmware, deployment, %{identifier: "smartrent_1234"})

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

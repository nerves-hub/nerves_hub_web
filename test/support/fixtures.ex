Code.compiler_options(ignore_module_conflict: true)
defmodule NervesHubCore.Fixtures do
  alias NervesHubCore.{Firmwares, Accounts, Devices, Deployments, Products, Certificate}

  @after_compile {__MODULE__, :compiler_options}

  def compiler_options(_, _), do: Code.compiler_options(ignore_module_conflict: false)

  @org_params %{name: "Test Org"}
  @org_key_params %{
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
    org_name: "mctesterson.com",
    email: "testy@mctesterson.com",
    password: "test_password"
  }
  @user_certificate_params %{
    description: "my test cert",
    serial: "158098897653878678601091983566405937658689714637"
  }

  def path(), do: Path.expand("../fixtures", __DIR__)

  def user_params(), do: @user_params

  def org_fixture(params \\ %{}) do
    {:ok, org} =
      params
      |> Enum.into(@org_params)
      |> Accounts.create_org()

    org
  end

  def org_key_fixture(%Accounts.Org{} = org, params \\ %{}) do
    {:ok, org_key} =
      %{org_id: org.id}
      |> Enum.into(params)
      |> Enum.into(@org_key_params)
      |> Enum.into(%{key: Ecto.UUID.generate()})
      |> Accounts.create_org_key()

    org_key
  end

  def user_fixture(%Accounts.Org{} = org, params \\ %{}) do
    user_params =
      params
      |> Enum.into(@user_params)

    {:ok, user} = Accounts.create_user(org, user_params)
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

  def product_fixture(%Accounts.Org{} = org, params) do
    {:ok, product} =
      %{org_id: org.id}
      |> Enum.into(params)
      |> Enum.into(@product_params)
      |> Products.create_product()

    product
  end

  def product_fixture(%{assigns: %{org: org}}, params) do
    {:ok, product} =
      %{org_id: org.id}
      |> Enum.into(params)
      |> Enum.into(@product_params)
      |> Products.create_product()

    product
  end

  def firmware_fixture(
        %Accounts.OrgKey{} = org_key,
        %Products.Product{} = product,
        params \\ %{}
      ) do
    {:ok, firmware} =
      %{org_key_id: org_key.id, product_id: product.id}
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
        %Accounts.Org{} = org,
        %Firmwares.Firmware{} = firmware,
        %Deployments.Deployment{} = deployment,
        params \\ %{}
      ) do
    {:ok, device} =
      %{
        org_id: org.id,
        target_deployment_id: deployment.id,
        last_known_firmware_id: firmware.id,
        tags: deployment.conditions["tags"]
      }
      |> Enum.into(params)
      |> Enum.into(@device_params)
      |> Devices.create_device()

    device
  end

  def device_certificate_fixture(%Devices.Device{} = device) do
    cert_file = Path.join(path(), "cfssl/device-1234-cert.pem")
    {:ok, cert} = File.read(cert_file)
    {not_before, not_after} = Certificate.get_validity(cert)
    {:ok, serial} = Certificate.get_serial_number(cert)
    params = %{serial: serial, not_before: not_before, not_after: not_after}
    {:ok, device_cert} = Devices.create_device_certificate(device, params)
    device_cert
  end

  def very_fixture() do
    org = org_fixture(%{name: "Very"})
    user = user_fixture(org, %{name: "Jeff"})
    product = product_fixture(org, %{name: "Hop"})
    org_key = org_key_fixture(org)
    firmware = firmware_fixture(org_key, product)
    deployment = deployment_fixture(firmware)
    device = device_fixture(org, firmware, deployment)

    %{
      org: org,
      device: device,
      org_key: org_key,
      user: user,
      firmware: firmware,
      deployment: deployment,
      product: product
    }
  end

  def smartrent_fixture() do
    org = org_fixture(%{name: "Smart Rent"})
    product = product_fixture(org, %{name: "Smart Rent Thing"})
    org_key = org_key_fixture(org)
    firmware = firmware_fixture(org_key, product)
    deployment = deployment_fixture(firmware)

    device = device_fixture(org, firmware, deployment, %{identifier: "smartrent_1234"})

    %{
      org: org,
      org_key: org_key,
      device: device,
      firmware: firmware,
      deployment: deployment,
      product: product
    }
  end
end

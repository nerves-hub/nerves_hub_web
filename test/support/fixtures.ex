Code.compiler_options(ignore_module_conflict: true)

defmodule NervesHubCore.Fixtures do
  alias NervesHubCore.{
    Accounts,
    Accounts.Org,
    Certificate,
    Devices,
    Deployments,
    Firmwares,
    Products,
    Repo
  }

  alias NervesHubCore.Support.Fwup

  @after_compile {__MODULE__, :compiler_options}

  def compiler_options(_, _), do: Code.compiler_options(ignore_module_conflict: false)

  @uploader Application.get_env(:nerves_hub_core, :firmware_upload)

  @org_params %{name: "Test Org"}

  @deployment_params %{
    name: "Test Deployment",
    conditions: %{
      "version" => "< 1.0.0",
      "tags" => ["beta", "beta-edge"]
    },
    is_active: false
  }
  @device_params %{tags: ["beta", "test"]}
  @product_params %{name: "valid product"}
  @user_certificate_params %{
    description: "my test cert",
    serial: "158098897653878678601091983566405937658689714637"
  }

  def path(), do: Path.expand("../fixtures", __DIR__)

  def user_params() do
    %{
      org_name: "org-#{counter()}.com",
      email: "email-#{counter()}@mctesterson.com",
      username: "user-#{counter()}",
      password: "test_password"
    }
  end

  def firmware_params(org_id, filepath) do
    %{
      architecture: "arm",
      author: "test_author",
      description: "test_description",
      platform: "rpi0",
      version: "1.0.0",
      vcs_identifier: "test_vcs_identifier",
      misc: "test_misc",
      upload_metadata: @uploader.metadata(org_id, filepath)
    }
  end

  def org_fixture(params \\ %{}) do
    {:ok, org} =
      params
      |> Enum.into(@org_params)
      |> Accounts.create_org()

    org
  end

  def org_key_fixture(%Accounts.Org{} = org) do
    params = %{org_id: org.id}

    fwup_key_name = "org_key-#{counter()}"
    Fwup.gen_key_pair(fwup_key_name)
    key = Fwup.get_public_key(fwup_key_name)

    {:ok, org_key} =
      Accounts.create_org_key(params |> Map.put(:key, key) |> Map.put(:name, fwup_key_name))

    org_key
  end

  def user_fixture(params \\ %{}) do
    {:ok, user} = params |> Enum.into(user_params()) |> Accounts.create_user()
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

  @spec firmware_file_fixture(OrgKey.t(), Product.t()) :: String.t()
  def firmware_file_fixture(
        %Accounts.OrgKey{} = org_key,
        %Products.Product{} = product,
        params \\ %{}
      ) do
    {:ok, filepath} =
      Fwup.create_signed_firmware(
        org_key.name,
        "unsigned-#{counter()}",
        "signed-#{counter()}",
        %{product: product.name} |> Enum.into(params)
      )

    filepath
  end

  def firmware_fixture(
        %Accounts.OrgKey{org_id: org_id} = org_key,
        %Products.Product{} = product,
        params \\ %{}
      ) do
    org = Repo.get!(Org, org_id)
    filepath = firmware_file_fixture(org_key, product, params)
    {:ok, firmware} = Firmwares.create_firmware(org, filepath)
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
        params \\ %{}
      ) do
    {:ok, device} =
      %{
        org_id: org.id,
        last_known_firmware_id: firmware.id,
        identifier: "device-#{counter()}"
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

  def standard_fixture() do
    user_name = "Jeff"
    org = org_fixture(%{name: user_name})
    user = user_fixture(%{name: user_name, orgs: [org]})
    product = product_fixture(org, %{name: "Hop"})
    org_key = org_key_fixture(org)
    firmware = firmware_fixture(org_key, product)
    deployment = deployment_fixture(firmware)
    device = device_fixture(org, firmware)

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

  def very_fixture() do
    org = org_fixture(%{name: "Very"})
    user = user_fixture(%{name: "Jeff", orgs: [org]})
    product = product_fixture(org, %{name: "Hop"})

    org_key = org_key_fixture(org)
    firmware = firmware_fixture(org_key, product)
    deployment = deployment_fixture(firmware)
    device = device_fixture(org, firmware, %{tags: ["beta", "beta-edge"]})
    device_certificate = device_certificate_fixture(device)

    %{
      deployment: deployment,
      device: device,
      device_certificate: device_certificate,
      firmware: firmware,
      org: org,
      org_key: org_key,
      product: product,
      user: user
    }
  end

  def smartrent_fixture() do
    org = org_fixture(%{name: "Smart Rent"})
    product = product_fixture(org, %{name: "Smart Rent Thing"})
    org_key = org_key_fixture(org)
    firmware = firmware_fixture(org_key, product)
    deployment = deployment_fixture(firmware)
    device = device_fixture(org, firmware, %{identifier: "smartrent_1234"})
    device_certificate = device_certificate_fixture(device)

    %{
      deployment: deployment,
      device: device,
      device_certificate: device_certificate,
      firmware: firmware,
      org: org,
      org_key: org_key,
      product: product
    }
  end

  defp counter do
    System.unique_integer([:positive])
  end
end

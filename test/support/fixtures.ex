Code.compiler_options(ignore_module_conflict: true)

defmodule NervesHubWebCore.Fixtures do
  alias NervesHubWebCore.{
    Accounts,
    Accounts.Org,
    Certificate,
    Devices,
    Deployments,
    Firmwares,
    Products,
    Repo
  }

  alias NervesHubWebCore.Support.Fwup

  @after_compile {__MODULE__, :compiler_options}

  def compiler_options(_, _), do: Code.compiler_options(ignore_module_conflict: false)

  @uploader Application.get_env(:nerves_hub_web_core, :firmware_upload)

  @org_params %{name: "Test-Org"}

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
      ttl: 1_000_000_000,
      upload_metadata: @uploader.metadata(org_id, filepath)
    }
  end

  def firmware_transfer_params(org_id, firmware_uuid) do
    %{
      org_id: org_id,
      firmware_uuid: firmware_uuid,
      remote_ip: "192.0.2.3",
      bytes_sent: 300000,
      bytes_total: 32184752,
      timestamp: DateTime.utc_now()
    }
  end

  def user_certificate_params() do
    %{
      description: "my test cert",
      serial: "158098897653878678601091983566405937658689714637",
      not_before: DateTime.utc_now(),
      not_after: Timex.shift(DateTime.utc_now(), minutes: 5),
      aki: "1234",
      ski: "5678"
    }
  end

  def org_fixture(user, params \\ %{}) do
    params = Enum.into(params, @org_params)
    {:ok, org} = Accounts.create_org(user, params)

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

  def ca_certificate_fixture(%Accounts.Org{} = org) do
    ca_key = X509.PrivateKey.new_ec(:secp256r1)
    ca = X509.Certificate.self_signed(ca_key, "CN=#{org.name}", template: :root_ca)

    {not_before, not_after} = NervesHubWebCore.Certificate.get_validity(ca)

    serial = NervesHubWebCore.Certificate.get_serial_number(ca)
    aki = NervesHubWebCore.Certificate.get_aki(ca)

    params = %{
      serial: serial,
      aki: aki,
      ski: NervesHubWebCore.Certificate.get_ski(ca),
      not_before: not_before,
      not_after: not_after,
      der: X509.Certificate.to_der(ca)
    }

    {:ok, db_cert} = Devices.create_ca_certificate(org, params)
    %{cert: ca, key: ca_key, db_cert: db_cert}
  end

  def user_fixture(params \\ %{}) do
    {:ok, user} = params |> Enum.into(user_params()) |> Accounts.create_user()
    {:ok, _certificate} = user_certificate_fixture(user)
    user
  end

  def user_certificate_fixture(%Accounts.User{} = user, params \\ %{}) do
    cert_params =
      Map.merge(user_certificate_params(), params)

    Accounts.create_user_certificate(user, cert_params)
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
    {:ok, firmware} = Firmwares.create_firmware(org, filepath, params)
    firmware
  end

  def firmware_transfer_fixture(org_id, firmware_uuid, params \\ %{}) do
    params =
      firmware_transfer_params(org_id, firmware_uuid)
      |> Map.merge(params)
    Firmwares.create_firmware_transfer(params)
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
    {:ok, metadata} = Firmwares.metadata_from_firmware(firmware)
    {:ok, device} =
      %{
        org_id: org.id,
        firmware_metadata: metadata,
        identifier: "device-#{counter()}"
      }
      |> Enum.into(params)
      |> Enum.into(@device_params)
      |> Devices.create_device()

    device
  end

  def device_certificate_fixture(_, _ \\ nil)
  def device_certificate_fixture(%Devices.Device{} = device, nil) do
    cert_file = Path.join(path(), "ssl/device-1234-cert.pem")
    {:ok, cert_pem} = File.read(cert_file)
    {:ok, cert} = X509.Certificate.from_pem(cert_pem)
    device_certificate_fixture(device, cert)
  end
  def device_certificate_fixture(%Devices.Device{} = device, cert) do
    serial = Certificate.get_serial_number(cert)
    {not_before, not_after} = Certificate.get_validity(cert)
    aki = Certificate.get_aki(cert)
    ski = Certificate.get_ski(cert)
    params = %{serial: serial, aki: aki, ski: ski, not_before: not_before, not_after: not_after}

    {:ok, device_cert} = Devices.create_device_certificate(device, params)
    device_cert
  end

  def standard_fixture() do
    user_name = "Jeff"
    user = user_fixture(%{name: user_name})
    org = org_fixture(user, %{name: user_name})
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
    user = user_fixture(%{name: "Jeff"})
    org = org_fixture(user, %{name: "Very"})
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
    user = user_fixture(%{name: "Frank"})
    org = org_fixture(user, %{name: "SmartRent"})
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

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
  @product_params %{name: "valid product", delta_updatable: true}

  @user_ca_key Path.expand("../fixtures/ssl/user-root-ca-key.pem", __DIR__)
  @user_ca_cert Path.expand("../fixtures/ssl/user-root-ca.pem", __DIR__)

  defdelegate reload(record), to: Repo

  def path(), do: Path.expand("../fixtures", __DIR__)

  def user_params() do
    %{
      org_name: "org-#{counter()}.com",
      email: "email-#{counter()}@mctesterson.com",
      username: "user-#{counter()}",
      password: "test_password"
    }
  end

  def user_certificate_params(%Accounts.User{} = user, params \\ %{}) do
    ca_key = File.read!(@user_ca_key) |> X509.PrivateKey.from_pem!()
    ca = File.read!(@user_ca_cert) |> X509.Certificate.from_pem!()

    key = X509.PrivateKey.new_ec(:secp256r1)

    cert =
      key
      |> X509.PublicKey.derive()
      |> X509.Certificate.new("/O=#{user.username}", ca, ca_key, validity: 1)

    {not_before, not_after} = NervesHubWebCore.Certificate.get_validity(cert)

    serial = Map.get(params, :serial) || NervesHubWebCore.Certificate.get_serial_number(cert)
    aki = NervesHubWebCore.Certificate.get_aki(cert)

    params = %{
      description: Map.get(params, :description) || user.username,
      serial: serial,
      aki: aki,
      ski: NervesHubWebCore.Certificate.get_ski(cert),
      not_before: not_before,
      not_after: not_after
    }

    %{cert: cert, key: key, params: params}
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
      bytes_sent: 300_000,
      bytes_total: 32_184_752,
      timestamp: DateTime.utc_now()
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

  def ca_certificate_fixture(%Accounts.Org{} = org, opts \\ []) do
    opts = Keyword.merge([template: :root_ca], opts)
    ca_key = X509.PrivateKey.new_ec(:secp256r1)
    ca = X509.Certificate.self_signed(ca_key, "CN=#{org.name}", opts)

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
    user
  end

  def user_certificate_fixture(%Accounts.User{} = user, params \\ %{}) do
    %{cert: cert, key: key, params: params} = user_certificate_params(user, params)
    {:ok, db_cert} = Accounts.create_user_certificate(user, params)
    %{cert: cert, key: key, db_cert: db_cert}
  end

  def product_fixture(_user, _org, params \\ %{})

  def product_fixture(%Accounts.User{} = user, %Accounts.Org{} = org, params) do
    params =
      %{org_id: org.id}
      |> Enum.into(params)
      |> Enum.into(@product_params)

    {:ok, product} = Products.create_product(user, params)
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

  def firmware_delta_fixture(%Firmwares.Firmware{id: source_id}, %Firmwares.Firmware{
        id: target_id,
        org_id: org_id,
        uuid: uuid
      }) do
    {:ok, firmware_delta} =
      Firmwares.insert_firmware_delta(%{
        source_id: source_id,
        target_id: target_id,
        upload_metadata: @uploader.metadata(org_id, "#{uuid}.fw")
      })

    firmware_delta
  end

  def firmware_transfer_fixture(org_id, firmware_uuid, params \\ %{}) do
    params =
      firmware_transfer_params(org_id, firmware_uuid)
      |> Map.merge(params)

    Firmwares.create_firmware_transfer(params)
  end

  def deployment_fixture(
        %Org{} = org,
        %Firmwares.Firmware{} = firmware,
        params \\ %{}
      ) do
    {:ok, deployment} =
      %{org_id: org.id, firmware_id: firmware.id}
      |> Enum.into(params)
      |> Enum.into(@deployment_params)
      |> Deployments.create_deployment()

    deployment
  end

  def device_fixture(
        %Accounts.Org{} = org,
        %Products.Product{} = product,
        %Firmwares.Firmware{} = firmware,
        params \\ %{}
      ) do
    {:ok, metadata} = Firmwares.metadata_from_firmware(firmware)

    {:ok, device} =
      %{
        org_id: org.id,
        product_id: product.id,
        firmware_metadata: metadata,
        identifier: "device-#{counter()}"
      }
      |> Enum.into(params)
      |> Enum.into(@device_params)
      |> Devices.create_device()

    device
  end

  def device_certificate_pem() do
    path()
    |> Path.join("ssl/device-1234-cert.pem")
    |> File.read!()
  end

  def device_certificate_authority_file() do
    path()
    |> Path.join("ssl/device-root-ca.pem")
  end

  def bad_device_certificate_authority_file() do
    path()
    |> Path.join("ssl/device-root-ca-key.pem")
  end

  def device_certificate_fixture(_, _ \\ nil)

  def device_certificate_fixture(%Devices.Device{} = device, nil) do
    cert = device_certificate_pem() |> X509.Certificate.from_pem!()
    device_certificate_fixture(device, cert)
  end

  def device_certificate_fixture(%Devices.Device{} = device, cert) do
    serial = Certificate.get_serial_number(cert)
    {not_before, not_after} = Certificate.get_validity(cert)
    aki = Certificate.get_aki(cert)
    ski = Certificate.get_ski(cert)
    der = Certificate.to_der(cert)
    params = %{serial: serial, aki: aki, ski: ski, not_before: not_before, not_after: not_after, der: der}

    {:ok, device_cert} = Devices.create_device_certificate(device, params)
    %{db_cert: device_cert, cert: cert}
  end

  def device_certificate_fixture_without_der(%Devices.Device{} = device, cert) do
    serial = Certificate.get_serial_number(cert)
    {not_before, not_after} = Certificate.get_validity(cert)
    aki = Certificate.get_aki(cert)
    ski = Certificate.get_ski(cert)
    params = %{serial: serial, aki: aki, ski: ski, not_before: not_before, not_after: not_after}

    {:ok, device_cert} = Devices.create_device_certificate(device, params)
    %{db_cert: device_cert, cert: cert}
  end

  def standard_fixture() do
    user_name = "Jeff"
    user = user_fixture(%{name: user_name})
    org = org_fixture(user, %{name: user_name})
    product = product_fixture(user, org, %{name: "Hop"})
    org_key = org_key_fixture(org)
    firmware = firmware_fixture(org_key, product)
    deployment = deployment_fixture(org, firmware)
    device = device_fixture(org, product, firmware)
    %{db_cert: device_certificate} = device_certificate_fixture(device)

    %{
      org: org,
      device: device,
      device_certificate: device_certificate,
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
    product = product_fixture(user, org, %{name: "Hop"})

    org_key = org_key_fixture(org)
    firmware = firmware_fixture(org_key, product)
    deployment = deployment_fixture(org, firmware)
    device = device_fixture(org, product, firmware, %{tags: ["beta", "beta-edge"]})
    %{db_cert: device_certificate} = device_certificate_fixture(device)

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
    product = product_fixture(user, org, %{name: "Smart Rent Thing"})
    org_key = org_key_fixture(org)
    firmware = firmware_fixture(org_key, product)
    deployment = deployment_fixture(org, firmware)
    device = device_fixture(org, product, firmware, %{identifier: "smartrent_1234"})
    %{db_cert: device_certificate} = device_certificate_fixture(device)

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

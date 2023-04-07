Code.compiler_options(ignore_module_conflict: true)

defmodule NervesHub.Fixtures do
  alias NervesHub.{
    Accounts,
    Accounts.Org,
    Accounts.OrgKey,
    Certificate,
    Devices,
    Deployments,
    Firmwares,
    Products,
    Products.Product,
    Repo
  }

  alias NervesHub.Support.Fwup

  @after_compile {__MODULE__, :compiler_options}

  def compiler_options(_, _), do: Code.compiler_options(ignore_module_conflict: false)

  @uploader Application.compile_env(:nerves_hub_www, :firmware_upload)

  @org_params %{name: "Test-Org"}

  @deployment_params %{
    name: "Test Deployment",
    conditions: %{
      "version" => "<= 1.0.0",
      "tags" => ["beta", "beta-edge"]
    },
    is_active: false
  }
  @device_params %{tags: ["beta", "beta-edge"]}
  @product_params %{name: "valid product", delta_updatable: true}

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

    {not_before, not_after} = NervesHub.Certificate.get_validity(ca)

    serial = NervesHub.Certificate.get_serial_number(ca)
    aki = NervesHub.Certificate.get_aki(ca)

    params = %{
      serial: serial,
      aki: aki,
      ski: NervesHub.Certificate.get_ski(ca),
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
    {:ok, firmware} = Firmwares.create_firmware(org, filepath)
    firmware
  end

  def firmware_delta_fixture(%Firmwares.Firmware{id: source_id}, %Firmwares.Firmware{
        id: target_id,
        org_id: org_id
      }) do
    {:ok, firmware_delta} =
      Firmwares.insert_firmware_delta(%{
        source_id: source_id,
        target_id: target_id,
        upload_metadata: @uploader.metadata(org_id, "#{Ecto.UUID.generate()}.fw")
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

  def device_certificate_authority_key_file() do
    path()
    |> Path.join("ssl/device-root-ca-key.pem")
  end

  def generate_certificate_authority_csr(ca_file, ca_key_file, code, dir) do
    verification_key_pem = Path.expand("verification-key.pem", dir)
    verification_csr_pem = Path.expand("verification-csr.pem", dir)
    verification_cert_pem = Path.expand("verification-cert.pem", dir)
    openssl(~w(genrsa -out #{verification_key_pem} 2048), dir)

    openssl(
      ~w(req -new -key #{verification_key_pem} -out #{verification_csr_pem} -subj /CN=#{code}),
      dir
    )

    openssl(
      ~w(x509 -req -in #{verification_csr_pem} -CA #{ca_file} -CAkey #{ca_key_file} -CAcreateserial -out #{verification_cert_pem} -days 500 -sha256),
      dir
    )

    %{
      verification_key_pem: verification_key_pem,
      verification_cert_pem: verification_cert_pem,
      verification_csr_pem: verification_csr_pem
    }
  end

  defp openssl(args, dir) do
    {_, 0} = System.cmd("openssl", args, cd: dir, stderr_to_stdout: true)
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

  def device_certificate_fixture(%Devices.Device{} = device, {:ECPrivateKey, _, _, _, _} = key) do
    csr = X509.CSR.new(key, "/O=tester/CN=#{device.identifier}")

    signer_cert_pem = File.read!(device_certificate_authority_file())
    signer_key_pem = File.read!(device_certificate_authority_key_file())
    {:ok, signer_cert} = X509.Certificate.from_pem(signer_cert_pem)
    {:ok, signer_key} = X509.PrivateKey.from_pem(signer_key_pem)

    subject_rdn = X509.CSR.subject(csr) |> X509.RDNSequence.to_string()
    public_key = X509.CSR.public_key(csr)

    now = DateTime.utc_now()

    not_before =
      now
      |> DateTime.to_unix()
      |> Kernel.-(12 * 60 * 60)
      |> DateTime.from_unix!()

    not_after = Map.put(now, :year, now.year + 30)

    cert =
      X509.Certificate.new(public_key, subject_rdn, signer_cert, signer_key,
        template: X509.Certificate.Template.new(%X509.Certificate.Template{
          serial: {:random, 20},
          validity: X509.Certificate.Validity.new(not_before, not_after),
          hash: :sha256,
          extensions: [
            basic_constraints: X509.Certificate.Extension.basic_constraints(false),
            key_usage: X509.Certificate.Extension.key_usage([:digitalSignature, :keyEncipherment]),
            ext_key_usage: X509.Certificate.Extension.ext_key_usage([:clientAuth]),
            subject_key_identifier: true,
            authority_key_identifier: true
          ]
        })
      )

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
    fixture = device_certificate_fixture(device, cert)

    {:ok, db_cert} =
      fixture.db_cert
      |> Ecto.Changeset.change(%{der: nil, fingerprint: nil, public_key_fingerprint: nil})
      |> Repo.update()

    %{fixture | db_cert: db_cert}
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

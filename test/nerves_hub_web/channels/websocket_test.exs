defmodule NervesHubWeb.WebsocketTest do
  use NervesHubWeb.ChannelCase

  import TrackerHelper

  alias NervesHub.Fixtures
  alias NervesHub.Accounts
  alias NervesHub.Deployments
  alias NervesHub.Deployments.Orchestrator
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Products
  alias NervesHub.Repo
  alias NervesHubWeb.DeviceEndpoint
  alias NervesHubWeb.Endpoint

  @valid_serial "device-1234"
  @valid_product "test-product"

  @device_port Application.compile_env(:nerves_hub, DeviceEndpoint) |> get_in([:https, :port])
  @web_port Application.compile_env(:nerves_hub, Endpoint) |> get_in([:http, :port])

  @bad_socket_config [
    uri: "wss://127.0.0.1:#{@device_port}/socket/websocket",
    json_parser: Jason,
    reconnect_after_msec: [500],
    rejoin_after_msec: [500],
    mint_opts: [
      protocols: [:http1],
      transport_opts: [
        verify: :verify_peer,
        versions: [:"tlsv1.2"],
        certfile: Path.expand("test/fixtures/ssl/device-fake.pem") |> to_charlist,
        keyfile: Path.expand("test/fixtures/ssl/device-fake-key.pem") |> to_charlist,
        cacertfile: Path.expand("test/fixtures/ssl/ca-fake.pem") |> to_charlist,
        server_name_indication: ~c"device.nerves-hub.org"
      ]
    ]
  ]

  @socket_config [
    uri: "wss://127.0.0.1:#{@device_port}/socket/websocket",
    json_parser: Jason,
    reconnect_after_msec: [500],
    rejoin_after_msec: [500],
    mint_opts: [
      protocols: [:http1],
      transport_opts: [
        verify: :verify_peer,
        versions: [:"tlsv1.2"],
        certfile: Path.expand("test/fixtures/ssl/device-1234-cert.pem") |> to_charlist,
        keyfile: Path.expand("test/fixtures/ssl/device-1234-key.pem") |> to_charlist,
        cacertfile: Path.expand("test/fixtures/ssl/ca.pem") |> to_charlist,
        server_name_indication: ~c"device.nerves-hub.org"
      ]
    ]
  ]

  def device_fixture(user, device_params \\ %{}, org \\ nil) do
    org = org || Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org)

    firmware =
      Fixtures.firmware_fixture(org_key, product, %{
        version: "0.0.1"
      })

    params = Enum.into(device_params, %{tags: ["beta", "beta-edge"]})

    device =
      Fixtures.device_fixture(
        org,
        product,
        firmware,
        params
      )

    {%{device | product: product, org: org}, firmware}
  end

  setup context do
    Mox.set_mox_from_context(context)
    user = Fixtures.user_fixture()

    {:ok,
     %{
       user: user
     }}
  end

  describe "socket auth" do
    test "Can connect and authenticate to channel using client ssl certificate", %{user: user} do
      {device, _firmware} = device_fixture(user, %{identifier: @valid_serial})

      Fixtures.device_certificate_fixture(device)

      {:ok, socket} = SocketClient.start_link(@socket_config)
      SocketClient.wait_connect(socket)
      SocketClient.join(socket, "device")
      SocketClient.wait_join(socket)

      device =
        NervesHub.Repo.get(Device, device.id)
        |> NervesHub.Repo.preload(:org)

      assert_online(device)

      SocketClient.close(socket)
    end

    test "Can connect and authenticate to channel using client ssl certificate with TLS 1.3", %{
      user: user
    } do
      {device, _firmware} = device_fixture(user, %{identifier: @valid_serial})

      Fixtures.device_certificate_fixture(device)

      config = [
        uri: "wss://127.0.0.1:#{@device_port}/socket/websocket",
        json_parser: Jason,
        reconnect_after_msec: [500],
        rejoin_after_msec: [500],
        mint_opts: [
          protocols: [:http1],
          transport_opts: [
            verify: :verify_peer,
            versions: [:"tlsv1.3"],
            certfile: Path.expand("test/fixtures/ssl/device-1234-cert.pem") |> to_charlist,
            keyfile: Path.expand("test/fixtures/ssl/device-1234-key.pem") |> to_charlist,
            cacertfile: Path.expand("test/fixtures/ssl/ca.pem") |> to_charlist,
            server_name_indication: ~c"device.nerves-hub.org"
          ]
        ]
      ]

      {:ok, socket} = SocketClient.start_link(config)
      SocketClient.wait_connect(socket)
      SocketClient.join(socket, "device")
      SocketClient.wait_join(socket)

      device =
        NervesHub.Repo.get(Device, device.id)
        |> NervesHub.Repo.preload(:org)

      assert_online(device)

      SocketClient.close(socket)
    end

    test "authentication rejected to channel using incorrect client ssl certificate" do
      {:ok, socket} = SocketClient.start_link(@bad_socket_config)
      refute SocketClient.connected?(socket)

      SocketClient.close(socket)
    end

    test "already registered expired certificate without signer CA can connect", %{user: user} do
      org = Fixtures.org_fixture(user, %{name: "custom_ca_test"})
      {device, _firmware} = device_fixture(user, %{identifier: @valid_serial}, org)

      ca_key = X509.PrivateKey.new_ec(:secp256r1)
      ca = X509.Certificate.self_signed(ca_key, "CN=#{org.name}", template: :root_ca)
      serial = NervesHub.Certificate.get_serial_number(ca)

      # Ensure this signer CA does not exist in the DB
      assert {:error, :not_found} = Devices.get_ca_certificate_by_serial(serial)

      key = X509.PrivateKey.new_ec(:secp256r1)

      not_before = Timex.now() |> Timex.shift(days: -2)
      not_after = Timex.now() |> Timex.shift(days: -1)

      cert =
        key
        |> X509.PublicKey.derive()
        |> X509.Certificate.new("CN=#{device.identifier}", ca, ca_key,
          validity: X509.Certificate.Validity.new(not_before, not_after)
        )

      # Verify our cert is indeed expired
      assert {:error, {:bad_cert, :cert_expired}} =
               :public_key.pkix_path_validation(
                 X509.Certificate.to_der(ca),
                 [X509.Certificate.to_der(cert)],
                 []
               )

      _ = Fixtures.device_certificate_fixture(device, cert)

      nerves_hub_ca_cert =
        Path.expand("test/fixtures/ssl/ca.pem")
        |> File.read!()
        |> X509.Certificate.from_pem!()

      opts = [
        uri: "wss://127.0.0.1:#{@device_port}/socket/websocket",
        json_parser: Jason,
        reconnect_after_msec: [500],
        rejoin_after_msec: [500],
        mint_opts: [
          protocols: [:http1],
          transport_opts: [
            verify: :verify_peer,
            versions: [:"tlsv1.2"],
            cert: X509.Certificate.to_der(cert),
            key: {:ECPrivateKey, X509.PrivateKey.to_der(key)},
            cacerts: [X509.Certificate.to_der(ca), X509.Certificate.to_der(nerves_hub_ca_cert)],
            server_name_indication: ~c"device.nerves-hub.org"
          ]
        ]
      ]

      {:ok, socket} = SocketClient.start_link(opts)
      SocketClient.wait_connect(socket)
      SocketClient.join(socket, "device")
      SocketClient.wait_join(socket)

      device =
        NervesHub.Repo.get(Device, device.id)
        |> NervesHub.Repo.preload(:org)

      assert_online(device)

      SocketClient.close(socket)
    end

    test "already registered expired certificate with expired signer CA can connect", %{
      user: user
    } do
      org = Fixtures.org_fixture(user, %{name: "custom_ca_test"})
      {device, _firmware} = device_fixture(user, %{identifier: @valid_serial}, org)

      not_before = Timex.now() |> Timex.shift(days: -3)
      not_after = Timex.now() |> Timex.shift(days: -1)
      validity = X509.Certificate.Validity.new(not_before, not_after)

      ca_key = X509.PrivateKey.new_ec(:secp256r1)

      ca =
        X509.Certificate.self_signed(ca_key, "CN=#{org.name}",
          template: :root_ca,
          validity: validity
        )

      serial = NervesHub.Certificate.get_serial_number(ca)

      # Ensure this signer CA does not exist in the DB
      assert {:error, :not_found} = Devices.get_ca_certificate_by_serial(serial)

      key = X509.PrivateKey.new_ec(:secp256r1)

      cert =
        key
        |> X509.PublicKey.derive()
        |> X509.Certificate.new("CN=#{device.identifier}", ca, ca_key, validity: validity)

      # Verify our cert is indeed expired
      assert {:error, {:bad_cert, :cert_expired}} =
               :public_key.pkix_path_validation(
                 X509.Certificate.to_der(ca),
                 [X509.Certificate.to_der(cert)],
                 []
               )

      _ = Fixtures.device_certificate_fixture(device, cert)

      nerves_hub_ca_cert =
        Path.expand("test/fixtures/ssl/ca.pem")
        |> File.read!()
        |> X509.Certificate.from_pem!()

      opts = [
        uri: "wss://127.0.0.1:#{@device_port}/socket/websocket",
        json_parser: Jason,
        reconnect_after_msec: [500],
        rejoin_after_msec: [500],
        mint_opts: [
          protocols: [:http1],
          transport_opts: [
            verify: :verify_peer,
            versions: [:"tlsv1.2"],
            cert: X509.Certificate.to_der(cert),
            key: {:ECPrivateKey, X509.PrivateKey.to_der(key)},
            cacerts: [X509.Certificate.to_der(ca), X509.Certificate.to_der(nerves_hub_ca_cert)],
            server_name_indication: ~c"device.nerves-hub.org"
          ]
        ]
      ]

      {:ok, socket} = SocketClient.start_link(opts)
      SocketClient.wait_connect(socket)
      SocketClient.join(socket, "device")
      SocketClient.wait_join(socket)

      device =
        NervesHub.Repo.get(Device, device.id)
        |> NervesHub.Repo.preload(:org)

      assert_online(device)

      SocketClient.close(socket)
    end
  end

  describe "shared secret auth NH1" do
    test "can register device with product key/secret", %{user: user} do
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      assert {:ok, auth} = Products.create_shared_secret_auth(product)

      identifier = Ecto.UUID.generate()
      refute Repo.get_by(Device, identifier: identifier)

      opts = [
        mint_opts: [protocols: [:http1]],
        uri: "ws://127.0.0.1:#{@web_port}/device-socket/websocket",
        headers: nh1_key_secret_headers(auth, identifier)
      ]

      params = %{
        "nerves_fw_uuid" => Ecto.UUID.generate(),
        "nerves_fw_product" => product.name,
        "nerves_fw_architecture" => "arm64",
        "nerves_fw_version" => "0.0.0",
        "nerves_fw_platform" => "test_host"
      }

      {:ok, socket} = SocketClient.start_link(opts)
      SocketClient.wait_connect(socket)
      SocketClient.join(socket, "device", params)
      SocketClient.wait_join(socket)

      assert device = Repo.get_by(Device, identifier: identifier) |> Repo.preload(:org)

      assert_online(device)

      SocketClient.close(socket)
    end

    test "rejects expired signature", %{user: user} do
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      assert {:ok, auth} = Products.create_shared_secret_auth(product)

      identifier = Ecto.UUID.generate()

      # Default allowance is 1 minute
      expired = System.system_time(:second) - 180

      opts = [
        mint_opts: [protocols: [:http1]],
        uri: "ws://127.0.0.1:#{@web_port}/device-socket/websocket",
        headers: nh1_key_secret_headers(auth, identifier, signed_at: expired)
      ]

      {:ok, socket} = SocketClient.start_link(opts)
      refute SocketClient.connected?(socket)

      SocketClient.close(socket)
    end

    test "can connect with device key/secret", %{user: user} do
      {device, _firmware} = device_fixture(user)
      assert {:ok, auth} = Devices.create_shared_secret_auth(device)

      opts = [
        mint_opts: [protocols: [:http1]],
        uri: "ws://127.0.0.1:#{@web_port}/device-socket/websocket",
        headers: nh1_key_secret_headers(auth, device.identifier)
      ]

      params = %{
        "nerves_fw_uuid" => Ecto.UUID.generate(),
        "nerves_fw_product" => device.product.name,
        "nerves_fw_architecture" => "arm64",
        "nerves_fw_version" => "0.0.0",
        "nerves_fw_platform" => "test_host"
      }

      {:ok, socket} = SocketClient.start_link(opts)
      SocketClient.wait_connect(socket)
      SocketClient.join(socket, "device", params)
      SocketClient.wait_join(socket)

      assert_online(device)

      SocketClient.close(socket)
    end

    test "rejects device key/secret with mismatched identifier", %{user: user} do
      {device, _firmware} = device_fixture(user)
      assert {:ok, auth} = Devices.create_shared_secret_auth(device)

      opts = [
        mint_opts: [protocols: [:http1]],
        uri: "ws://127.0.0.1:#{@web_port}/device-socket/websocket",
        headers: nh1_key_secret_headers(auth, "this-is-not-the-device-identifier")
      ]

      {:ok, socket} = SocketClient.start_link(opts)
      refute SocketClient.connected?(socket)
      refute_online(device)
      SocketClient.close(socket)
    end

    test "rejects unknown secret keys", %{user: user} do
      {device, _fw} = device_fixture(user)

      bad_auths = [
        %Devices.SharedSecretAuth{key: "nhd_12345unknown", secret: "shhhhh"},
        %Devices.SharedSecretAuth{key: "badprefix_12345unknown", secret: "shhhhh"},
        %Products.SharedSecretAuth{key: "nhp_12345unknown", secret: "shhhhh"},
        %Products.SharedSecretAuth{key: "badproduct_12345unknown", secret: "shhhhh"}
      ]

      for auth <- bad_auths do
        opts = [
          mint_opts: [protocols: [:http1]],
          uri: "ws://127.0.0.1:#{@web_port}/device-socket/websocket",
          headers: nh1_key_secret_headers(auth, device.identifier)
        ]

        {:ok, socket} = SocketClient.start_link(opts)
        refute SocketClient.connected?(socket)
        refute_online(device)
        SocketClient.close(socket)
      end
    end
  end

  test "returns 401 and a nice message if auth is missing" do
    opts = [
      mint_opts: [protocols: [:http1]],
      uri: "ws://127.0.0.1:#{@web_port}/device-socket/websocket"
    ]

    {:ok, socket} = SocketClient.start_link(opts)

    SocketClient.wait_connect(socket)

    refute SocketClient.connected?(socket)

    assigns = SocketClient.state(socket).assigns

    assert assigns.error_code == 401

    assert assigns.error_reason ==
             "no certificate pair or shared secrets connection settings were provided"

    SocketClient.close(socket)
  end

  defp nh1_key_secret_headers(auth, identifier, opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:key_digest, :sha256)
      |> Keyword.put_new(:key_iterations, 1000)
      |> Keyword.put_new(:key_length, 32)
      |> Keyword.put_new(:signed_at, System.system_time(:second))

    alg = "NH1-HMAC-#{opts[:key_digest]}-#{opts[:key_iterations]}-#{opts[:key_length]}"

    salt = """
    NH1:device-socket:shared-secret:connect

    x-nh-alg=#{alg}
    x-nh-key=#{auth.key}
    x-nh-time=#{opts[:signed_at]}
    """

    [
      {"x-nh-alg", alg},
      {"x-nh-key", auth.key},
      {"x-nh-time", to_string(opts[:signed_at])},
      {"x-nh-signature", Plug.Crypto.sign(auth.secret, salt, identifier, opts)}
    ]
  end

  describe "firmware update" do
    test "receives update message when eligible deployment is available", %{user: user} do
      {device, firmware} = device_fixture(user, %{identifier: @valid_serial})

      firmware = NervesHub.Repo.preload(firmware, :product)
      Fixtures.device_certificate_fixture(device)

      org = %Accounts.Org{id: device.org_id}
      org_key = Fixtures.org_key_fixture(org)

      firmware2 =
        Fixtures.firmware_fixture(org_key, firmware.product, %{
          version: "0.0.2"
        })

      Fixtures.firmware_delta_fixture(firmware, firmware2)

      Fixtures.deployment_fixture(org, firmware2, %{
        name: "a different name",
        conditions: %{
          "version" => ">= 0.0.1",
          "tags" => ["beta", "beta-edge"]
        }
      })
      |> Deployments.update_deployment(%{is_active: true})

      {:ok, socket} = SocketClient.start_link(@socket_config)
      SocketClient.wait_connect(socket)
      SocketClient.join(socket, "device")
      SocketClient.wait_join(socket)
      update = SocketClient.wait_update(socket)
      assert %{"update_available" => true, "firmware_url" => _, "firmware_meta" => %{}} = update

      device =
        Device
        |> NervesHub.Repo.get(device.id)
        |> NervesHub.Repo.preload(:org)

      assert Time.diff(DateTime.utc_now(), device.last_communication) < 2

      SocketClient.close(socket)
    end

    test "receives update message when a deployment gets a new version", %{user: user} do
      {device, firmware} = device_fixture(user, %{identifier: @valid_serial})

      device = NervesHub.Repo.preload(device, :org)
      firmware = NervesHub.Repo.preload(firmware, :product)

      Fixtures.device_certificate_fixture(device)
      org_key = Fixtures.org_key_fixture(device.org)

      deployment =
        Fixtures.deployment_fixture(device.org, firmware, %{
          name: "a different name",
          conditions: %{
            "tags" => ["beta", "beta-edge"]
          }
        })

      {:ok, deployment} =
        Deployments.update_deployment(deployment, %{
          is_active: true
        })

      {:ok, socket} = SocketClient.start_link(@socket_config)
      SocketClient.wait_connect(socket)
      SocketClient.join(socket, "device")
      SocketClient.wait_join(socket)
      reply = SocketClient.reply(socket)

      assert %{} = reply

      new_firmware = Fixtures.firmware_fixture(org_key, firmware.product, %{version: "0.0.2"})

      {:ok, deployment} =
        Deployments.update_deployment(deployment, %{
          firmware_id: new_firmware.id
        })

      # This is what the orchestrator process will do
      Orchestrator.trigger_update(deployment)

      message = SocketClient.wait_update(socket)

      assert message["update_available"]

      SocketClient.close(socket)
    end

    test "does not receive update message when current_version matches target_version", %{
      user: user
    } do
      {device, firmware} =
        device_fixture(user, %{identifier: @valid_serial, product: @valid_product})

      Fixtures.device_certificate_fixture(device)

      query_uuid = firmware.uuid

      {:ok, socket} = SocketClient.start_link(@socket_config)
      SocketClient.wait_connect(socket)
      SocketClient.join(socket, "device")
      SocketClient.wait_join(socket)
      reply = SocketClient.reply(socket)
      assert %{} = reply

      device = Repo.preload(device, :org)

      updated_device =
        Devices.get_device_by_identifier(device.org, device.identifier)
        |> elem(1)
        |> Repo.preload(:org)

      assert updated_device.firmware_metadata.uuid == query_uuid
      assert_online(device)
      assert Time.diff(DateTime.utc_now(), updated_device.last_communication) < 2

      SocketClient.close(socket)
    end

    test "checks version requirements on connect", %{user: user} do
      {device, firmware} =
        device_fixture(user, %{identifier: @valid_serial, product: @valid_product})

      org = %Accounts.Org{id: device.org_id}

      Fixtures.deployment_fixture(org, firmware, %{
        name: "a different name",
        conditions: %{
          "version" => "~> 0.0.1",
          "tags" => ["beta", "beta-edge"]
        }
      })
      |> Deployments.update_deployment(%{is_active: true})

      device = Deployments.set_deployment(device)
      assert device.deployment_id

      Fixtures.device_certificate_fixture(device)

      {:ok, socket} = SocketClient.start_link(@socket_config)
      SocketClient.wait_connect(socket)

      # Device has updated and no longer matches the attached deployment
      SocketClient.join(socket, "device", %{
        "nerves_fw_uuid" => Ecto.UUID.generate(),
        "nerves_fw_product" => "test",
        "nerves_fw_architecture" => "arm",
        "nerves_fw_platform" => "tester",
        "nerves_fw_version" => "0.1.0"
      })

      SocketClient.wait_join(socket)

      Process.sleep(100)

      device = Repo.reload(device)
      refute device.deployment_id

      SocketClient.close(socket)
    end
  end

  describe "Custom CA Signers" do
    test "valid certificate can connect", %{user: user} do
      org = Fixtures.org_fixture(user, %{name: "custom_ca_test"})
      {device, _firmware} = device_fixture(user, %{identifier: @valid_serial}, org)

      %{cert: ca, key: ca_key} = Fixtures.ca_certificate_fixture(org)

      key = X509.PrivateKey.new_ec(:secp256r1)

      cert =
        key
        |> X509.PublicKey.derive()
        |> X509.Certificate.new("CN=#{device.identifier}", ca, ca_key)

      nerves_hub_ca_cert =
        Path.expand("test/fixtures/ssl/ca.pem")
        |> File.read!()
        |> X509.Certificate.from_pem!()

      opts = [
        uri: "wss://127.0.0.1:#{@device_port}/socket/websocket",
        json_parser: Jason,
        reconnect_after_msec: [500],
        rejoin_after_msec: [500],
        mint_opts: [
          protocols: [:http1],
          transport_opts: [
            verify: :verify_peer,
            versions: [:"tlsv1.2"],
            cert: X509.Certificate.to_der(cert),
            key: {:ECPrivateKey, X509.PrivateKey.to_der(key)},
            cacerts: [X509.Certificate.to_der(ca), X509.Certificate.to_der(nerves_hub_ca_cert)],
            server_name_indication: ~c"device.nerves-hub.org"
          ]
        ]
      ]

      {:ok, socket} = SocketClient.start_link(opts)
      SocketClient.wait_connect(socket)
      SocketClient.join(socket, "device")
      SocketClient.wait_join(socket)

      device =
        NervesHub.Repo.get(Device, device.id)
        |> NervesHub.Repo.preload(:org)

      assert_online(device)

      SocketClient.close(socket)
    end

    test "vaild certificate expired signer can connect", %{user: user} do
      org = Fixtures.org_fixture(user, %{name: "custom_ca_test"})
      {device, _firmware} = device_fixture(user, %{identifier: @valid_serial}, org)

      not_before = Timex.now() |> Timex.shift(days: -1)
      not_after = Timex.now() |> Timex.shift(seconds: 1)

      template =
        X509.Certificate.Template.new(:root_ca,
          validity: X509.Certificate.Validity.new(not_before, not_after)
        )

      %{cert: ca, key: ca_key} = Fixtures.ca_certificate_fixture(org, template: template)

      key = X509.PrivateKey.new_ec(:secp256r1)

      cert =
        key
        |> X509.PublicKey.derive()
        |> X509.Certificate.new("CN=#{device.identifier}", ca, ca_key)

      Fixtures.device_certificate_fixture(device, cert)

      nerves_hub_ca_cert =
        Path.expand("test/fixtures/ssl/ca.pem")
        |> File.read!()
        |> X509.Certificate.from_pem!()

      opts = [
        uri: "wss://127.0.0.1:#{@device_port}/socket/websocket",
        json_parser: Jason,
        reconnect_after_msec: [500],
        rejoin_after_msec: [500],
        mint_opts: [
          protocols: [:http1],
          transport_opts: [
            verify: :verify_peer,
            versions: [:"tlsv1.2"],
            cert: X509.Certificate.to_der(cert),
            key: {:ECPrivateKey, X509.PrivateKey.to_der(key)},
            cacerts: [X509.Certificate.to_der(ca), X509.Certificate.to_der(nerves_hub_ca_cert)],
            server_name_indication: ~c"device.nerves-hub.org"
          ]
        ]
      ]

      :timer.sleep(2_000)

      {:ok, socket} = SocketClient.start_link(opts)
      SocketClient.wait_connect(socket)
      SocketClient.join(socket, "device")
      SocketClient.wait_join(socket)

      device =
        NervesHub.Repo.get(Device, device.id)
        |> NervesHub.Repo.preload(:org)

      assert_online(device)

      SocketClient.close(socket)
    end

    test "ca signer last used is updated", %{user: user} do
      org = Fixtures.org_fixture(user, %{name: "ca_cert_is_updated"})

      {device, _firmware} = device_fixture(user, %{identifier: @valid_serial}, org)

      %{cert: ca, key: ca_key, db_cert: %{last_used: last_used}} =
        Fixtures.ca_certificate_fixture(org)

      key = X509.PrivateKey.new_ec(:secp256r1)

      cert =
        key
        |> X509.PublicKey.derive()
        |> X509.Certificate.new("CN=#{device.identifier}", ca, ca_key)

      nerves_hub_ca_cert =
        Path.expand("test/fixtures/ssl/ca.pem")
        |> File.read!()
        |> X509.Certificate.from_pem!()

      opts = [
        uri: "wss://127.0.0.1:#{@device_port}/socket/websocket",
        json_parser: Jason,
        reconnect_after_msec: [500],
        rejoin_after_msec: [500],
        mint_opts: [
          protocols: [:http1],
          transport_opts: [
            verify: :verify_peer,
            versions: [:"tlsv1.2"],
            cert: X509.Certificate.to_der(cert),
            key: {:ECPrivateKey, X509.PrivateKey.to_der(key)},
            cacerts: [X509.Certificate.to_der(ca), X509.Certificate.to_der(nerves_hub_ca_cert)],
            server_name_indication: ~c"device.nerves-hub.org"
          ]
        ]
      ]

      {:ok, socket} = SocketClient.start_link(opts)
      SocketClient.wait_connect(socket)
      SocketClient.join(socket, "device")
      SocketClient.wait_join(socket)
      GenServer.stop(socket)

      {:ok, socket} = SocketClient.start_link(opts)
      SocketClient.wait_connect(socket)
      SocketClient.join(socket, "device")
      SocketClient.wait_join(socket)

      [%{last_used: updated_last_used}] = Devices.get_ca_certificates(org)

      assert last_used != updated_last_used

      SocketClient.close(socket)
    end
  end

  describe "archives" do
    test "on connect receive an archive", %{user: user} do
      org = Fixtures.org_fixture(user)
      org_key = Fixtures.org_key_fixture(org)

      {device, firmware} = device_fixture(user, %{identifier: @valid_serial}, org)

      firmware = Repo.preload(firmware, [:product])
      product = firmware.product

      archive = Fixtures.archive_fixture(org_key, product)

      deployment =
        Fixtures.deployment_fixture(org, firmware, %{
          name: "beta",
          conditions: %{
            "tags" => ["beta"]
          }
        })

      {:ok, deployment} = Deployments.update_deployment(deployment, %{archive_id: archive.id})
      {:ok, _deployment} = Deployments.update_deployment(deployment, %{is_active: true})

      Fixtures.device_certificate_fixture(device)

      {:ok, socket} = SocketClient.start_link(@socket_config)
      SocketClient.wait_connect(socket)
      SocketClient.join(socket, "device", %{"device_api_version" => "2.0.0"})
      SocketClient.wait_join(socket)

      device =
        NervesHub.Repo.get(Device, device.id)
        |> NervesHub.Repo.preload(:org)

      assert_online(device)

      archive = SocketClient.wait_archive(socket)
      assert %{"url" => _, "version" => _} = archive

      SocketClient.close(socket)
    end
  end
end

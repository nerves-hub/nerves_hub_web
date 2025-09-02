defmodule NervesHubWeb.WebsocketTest do
  use NervesHubWeb.ChannelCase

  import TrackerHelper

  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.AuditLog
  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.Distributed.Orchestrator
  alias NervesHub.Products
  alias NervesHub.Repo
  alias NervesHub.Support.Utils
  alias NervesHubWeb.DeviceEndpoint
  alias NervesHubWeb.Endpoint

  import Ecto.Query

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
        certfile: Path.expand("test/fixtures/ssl/device-fake.pem") |> to_charlist(),
        keyfile: Path.expand("test/fixtures/ssl/device-fake-key.pem") |> to_charlist(),
        cacertfile: Path.expand("test/fixtures/ssl/ca-fake.pem") |> to_charlist(),
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
        certfile: Path.expand("test/fixtures/ssl/device-1234-cert.pem") |> to_charlist(),
        keyfile: Path.expand("test/fixtures/ssl/device-1234-key.pem") |> to_charlist(),
        cacertfile: Path.expand("test/fixtures/ssl/ca.pem") |> to_charlist(),
        server_name_indication: ~c"device.nerves-hub.org"
      ]
    ]
  ]

  def device_fixture(dir, user, device_params \\ %{}, org \\ nil) do
    org = org || Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, dir)

    firmware =
      Fixtures.firmware_fixture(org_key, product, %{
        version: "0.0.1",
        dir: dir
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

  setup do
    user = Fixtures.user_fixture()

    {:ok,
     %{
       user: user
     }}
  end

  describe "socket auth" do
    @describetag :tmp_dir

    test "Can connect and authenticate to channel using client ssl certificate", %{
      user: user,
      tmp_dir: tmp_dir
    } do
      {device, _firmware} = device_fixture(tmp_dir, user, %{identifier: @valid_serial})

      Fixtures.device_certificate_fixture(device)

      subscribe_for_updates(device)

      {:ok, socket} = SocketClient.start_link(@socket_config)
      SocketClient.join_and_wait(socket)

      assert_online_and_available(device)

      close_socket_cleanly(socket)
    end

    test "Can connect and authenticate to channel using client ssl certificate with TLS 1.3", %{
      user: user,
      tmp_dir: tmp_dir
    } do
      {device, _firmware} = device_fixture(tmp_dir, user, %{identifier: @valid_serial})

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
            certfile: Path.expand("test/fixtures/ssl/device-1234-cert.pem") |> to_charlist(),
            keyfile: Path.expand("test/fixtures/ssl/device-1234-key.pem") |> to_charlist(),
            cacertfile: Path.expand("test/fixtures/ssl/ca.pem") |> to_charlist(),
            server_name_indication: ~c"device.nerves-hub.org"
          ]
        ]
      ]

      subscribe_for_updates(device)

      {:ok, socket} = SocketClient.start_link(config)
      SocketClient.join_and_wait(socket)

      assert_connection_change()
      assert_online_and_available(device)

      close_socket_cleanly(socket)
    end

    test "authentication rejected to channel using incorrect client ssl certificate" do
      {:ok, socket} = SocketClient.start_link(@bad_socket_config)
      SocketClient.wait_connect(socket)

      refute SocketClient.connected?(socket)
    end

    test "already registered expired certificate without signer CA can connect", %{
      user: user,
      tmp_dir: tmp_dir
    } do
      org = Fixtures.org_fixture(user, %{name: "custom_ca_test"})
      {device, _firmware} = device_fixture(tmp_dir, user, %{identifier: @valid_serial}, org)

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

      subscribe_for_updates(device)

      {:ok, socket} = SocketClient.start_link(opts)
      SocketClient.join_and_wait(socket)

      assert_connection_change()
      assert_online_and_available(device)

      close_socket_cleanly(socket)
    end

    test "already registered expired certificate with expired signer CA can connect", %{
      user: user,
      tmp_dir: tmp_dir
    } do
      org = Fixtures.org_fixture(user, %{name: "custom_ca_test"})
      {device, _firmware} = device_fixture(tmp_dir, user, %{identifier: @valid_serial}, org)

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

      subscribe_for_updates(device)

      {:ok, socket} = SocketClient.start_link(opts)
      SocketClient.join_and_wait(socket)

      assert_connection_change()
      assert_online_and_available(device)

      close_socket_cleanly(socket)
    end
  end

  describe "shared secret auth NH1" do
    @describetag :tmp_dir

    setup do
      Application.put_env(:nerves_hub, NervesHubWeb.DeviceSocket, shared_secrets: [enabled: true])

      on_exit(fn ->
        Application.put_env(:nerves_hub, NervesHubWeb.DeviceSocket, shared_secrets: [enabled: false])
      end)
    end

    test "can register device with product key/secret", %{user: user} do
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      assert {:ok, auth} = Products.create_shared_secret_auth(product)

      identifier = Ecto.UUID.generate()
      refute Repo.get_by(Device, identifier: identifier)

      opts = [
        mint_opts: [protocols: [:http1]],
        uri: "ws://127.0.0.1:#{@web_port}/device-socket/websocket",
        headers: Utils.nh1_key_secret_headers(auth, identifier)
      ]

      params = %{
        "nerves_fw_uuid" => Ecto.UUID.generate(),
        "nerves_fw_product" => product.name,
        "nerves_fw_architecture" => "arm64",
        "nerves_fw_version" => "0.0.0",
        "nerves_fw_platform" => "test_host"
      }

      subscribe_for_updates(%Device{identifier: identifier})

      {:ok, socket} = SocketClient.start_link(opts)
      SocketClient.join_and_wait(socket, params)

      assert device = Repo.get_by(Device, identifier: identifier)

      assert_connection_change()
      assert_online_and_available(device)

      close_socket_cleanly(socket)
    end

    test "can register device with product key/secret, don't rely on header order", %{user: user} do
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      assert {:ok, auth} = Products.create_shared_secret_auth(product)

      identifier = Ecto.UUID.generate()
      refute Repo.get_by(Device, identifier: identifier)

      opts = [
        mint_opts: [protocols: [:http1]],
        uri: "ws://127.0.0.1:#{@web_port}/device-socket/websocket",
        headers: Utils.nh1_key_secret_headers(auth, identifier) |> Enum.reverse()
      ]

      params = %{
        "nerves_fw_uuid" => Ecto.UUID.generate(),
        "nerves_fw_product" => product.name,
        "nerves_fw_architecture" => "arm64",
        "nerves_fw_version" => "0.0.0",
        "nerves_fw_platform" => "test_host"
      }

      subscribe_for_updates(%Device{identifier: identifier})

      {:ok, socket} = SocketClient.start_link(opts)
      SocketClient.join_and_wait(socket, params)

      assert device = Repo.get_by(Device, identifier: identifier)

      assert_connection_change()
      assert_online_and_available(device)

      close_socket_cleanly(socket)
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
        headers: Utils.nh1_key_secret_headers(auth, identifier, signed_at: expired)
      ]

      {:ok, socket} = SocketClient.start_link(opts)
      SocketClient.wait_connect(socket)

      refute SocketClient.connected?(socket)
    end

    test "can connect with device key/secret", %{user: user, tmp_dir: tmp_dir} do
      {device, _firmware} = device_fixture(tmp_dir, user)
      assert {:ok, auth} = Devices.create_shared_secret_auth(device)

      opts = [
        mint_opts: [protocols: [:http1]],
        uri: "ws://127.0.0.1:#{@web_port}/device-socket/websocket",
        headers: Utils.nh1_key_secret_headers(auth, device.identifier)
      ]

      params = %{
        "nerves_fw_uuid" => Ecto.UUID.generate(),
        "nerves_fw_product" => device.product.name,
        "nerves_fw_architecture" => "arm64",
        "nerves_fw_version" => "0.0.0",
        "nerves_fw_platform" => "test_host"
      }

      subscribe_for_updates(device)

      {:ok, socket} = SocketClient.start_link(opts)
      SocketClient.join_and_wait(socket, params)

      assert_connection_change()
      assert_online_and_available(device)

      close_socket_cleanly(socket)
    end

    test "rejects device key/secret with mismatched identifier", %{user: user, tmp_dir: tmp_dir} do
      {device, _firmware} = device_fixture(tmp_dir, user)
      assert {:ok, auth} = Devices.create_shared_secret_auth(device)

      opts = [
        mint_opts: [protocols: [:http1]],
        uri: "ws://127.0.0.1:#{@web_port}/device-socket/websocket",
        headers: Utils.nh1_key_secret_headers(auth, "this-is-not-the-device-identifier")
      ]

      {:ok, socket} = SocketClient.start_link(opts)
      SocketClient.wait_connect(socket)

      refute SocketClient.connected?(socket)
      refute_online(device)
    end

    test "rejects unknown secret keys", %{user: user, tmp_dir: tmp_dir} do
      {device, _fw} = device_fixture(tmp_dir, user)

      bad_auths = [
        %Devices.SharedSecretAuth{key: "nhd_12345unknown", secret: "not_telling"},
        %Devices.SharedSecretAuth{key: "bad_prefix_12345unknown", secret: "not_telling"},
        %Products.SharedSecretAuth{key: "nhp_12345unknown", secret: "not_telling"},
        %Products.SharedSecretAuth{key: "bad_product_12345unknown", secret: "not_telling"}
      ]

      for auth <- bad_auths do
        opts = [
          mint_opts: [protocols: [:http1]],
          uri: "ws://127.0.0.1:#{@web_port}/device-socket/websocket",
          headers: Utils.nh1_key_secret_headers(auth, device.identifier)
        ]

        {:ok, socket} = SocketClient.start_link(opts)
        SocketClient.wait_connect(socket)

        refute SocketClient.connected?(socket)
        refute_online(device)
      end
    end

    test "safely rejects if an ETF is passed in as a device identifier", %{user: user} do
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      assert {:ok, auth} = Products.create_shared_secret_auth(product)

      identifier = &Ecto.UUID.generate/0

      opts = [
        mint_opts: [protocols: [:http1]],
        uri: "ws://127.0.0.1:#{@web_port}/device-socket/websocket",
        headers: Utils.nh1_key_secret_headers(auth, identifier)
      ]

      {:ok, socket} = SocketClient.start_link(opts)

      SocketClient.wait_connect(socket)

      refute SocketClient.connected?(socket)
    end
  end

  describe "duplicate connections using the same device id" do
    @describetag :tmp_dir

    setup do
      Application.put_env(:nerves_hub, NervesHubWeb.DeviceSocket, shared_secrets: [enabled: true])

      on_exit(fn ->
        Application.put_env(:nerves_hub, NervesHubWeb.DeviceSocket, shared_secrets: [enabled: false])
      end)
    end

    test "closes duplicate connections during connection", %{user: user} do
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      assert {:ok, auth} = Products.create_shared_secret_auth(product)

      identifier = Ecto.UUID.generate()
      refute Repo.get_by(Device, identifier: identifier)

      opts = [
        mint_opts: [protocols: [:http1]],
        uri: "ws://127.0.0.1:#{@web_port}/device-socket/websocket",
        headers: Utils.nh1_key_secret_headers(auth, identifier)
      ]

      params = %{
        "nerves_fw_uuid" => Ecto.UUID.generate(),
        "nerves_fw_product" => product.name,
        "nerves_fw_architecture" => "arm64",
        "nerves_fw_version" => "0.0.0",
        "nerves_fw_platform" => "test_host"
      }

      subscribe_for_updates(%Device{identifier: identifier})

      {:ok, socket} = SocketClient.start_link(opts)
      SocketClient.join_and_wait(socket, params)

      assert_connection_change()

      assert device = Repo.get_by(Device, identifier: identifier)

      assert_online_and_available(device)

      {:ok, new_connection} = SocketClient.start_link(opts)
      SocketClient.join_and_wait(new_connection, params)

      assert_connection_change()

      # this needs a bit of time to happen
      eventually refute SocketClient.connected?(socket)

      assert SocketClient.connected?(new_connection)
      assert_online_and_available(device)

      close_socket_cleanly(new_connection)
    end
  end

  describe "connection status is tracked" do
    test "set connection status upon connection and disconnection", %{user: user} do
      Application.put_env(:nerves_hub, NervesHubWeb.DeviceSocket, shared_secrets: [enabled: true])

      on_exit(fn ->
        Application.put_env(:nerves_hub, NervesHubWeb.DeviceSocket, shared_secrets: [enabled: false])
      end)

      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      assert {:ok, auth} = Products.create_shared_secret_auth(product)

      identifier = Ecto.UUID.generate()
      refute Repo.get_by(Device, identifier: identifier)

      opts = [
        mint_opts: [protocols: [:http1]],
        uri: "ws://127.0.0.1:#{@web_port}/device-socket/websocket",
        headers: Utils.nh1_key_secret_headers(auth, identifier)
      ]

      params = %{
        "nerves_fw_uuid" => Ecto.UUID.generate(),
        "nerves_fw_product" => product.name,
        "nerves_fw_architecture" => "arm64",
        "nerves_fw_version" => "0.0.0",
        "nerves_fw_platform" => "test_host"
      }

      subscribe_for_updates(%Device{identifier: identifier})

      {:ok, socket} = SocketClient.start_link(opts)

      SocketClient.join_and_wait(socket, params)

      assert_connection_change()

      assert device = Repo.get_by(Device, identifier: identifier)
      assert device_connection = Connections.get_latest_for_device(device.id)

      # the connected status goes from `:connecting` to `:connected`, signifying
      # that it is ready to receive updates, which can take a second or two.
      # using this different status allows us to tell the orchestrator to only
      # schedule update for devices that have "finished" connecting
      eventually assert(Connections.get_latest_for_device(device.id).status == :connected), 3_000

      assert recent_datetime(device_connection.established_at)
      assert recent_datetime(device_connection.last_seen_at)
      assert device_connection.disconnected_at == nil

      _ = SocketClient.clean_close(socket)
      :timer.sleep(10)

      assert device_connection = Connections.get_latest_for_device(device.id)
      assert device_connection.status == :disconnected

      assert recent_datetime(device_connection.established_at)
      assert recent_datetime(device_connection.last_seen_at)
      assert recent_datetime(device_connection.disconnected_at)
    end

    defp recent_datetime(datetime) do
      DateTime.diff(DateTime.utc_now(), datetime, :second) <= 5
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
  end

  describe "firmware update" do
    @describetag :tmp_dir

    test "receives update message when a deployment gets a new version", %{
      user: user,
      tmp_dir: tmp_dir
    } do
      org = Fixtures.org_fixture(user)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      product = Fixtures.product_fixture(user, org)

      firmware =
        Fixtures.firmware_fixture(org_key, product, %{
          version: "0.0.1",
          dir: tmp_dir
        })
        |> Repo.preload([:product])

      {:ok, deployment_group} =
        Fixtures.deployment_group_fixture(org, firmware, %{
          name: "a different name",
          conditions: %{
            "version" => "<= 1.0.0",
            "tags" => ["beta"]
          }
        })
        |> ManagedDeployments.update_deployment_group(%{is_active: true})

      device =
        Fixtures.device_fixture(
          org,
          product,
          firmware,
          %{
            tags: ["beta", "beta-edge"],
            identifier: @valid_serial,
            deployment_id: deployment_group.id
          }
        )

      Fixtures.device_certificate_fixture(device)

      subscribe_for_updates(device)

      {:ok, socket} = SocketClient.start_link(@socket_config)
      SocketClient.join_and_wait(socket)

      assert_online_and_available(device)

      new_firmware =
        Fixtures.firmware_fixture(org_key, firmware.product, %{version: "0.0.2", dir: tmp_dir})

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{
          firmware_id: new_firmware.id
        })

      # This is what the orchestrator process will do
      Orchestrator.trigger_update(deployment_group)

      message = SocketClient.wait_update(socket)

      assert message["update_available"]

      close_socket_cleanly(socket)
    end

    test "does not receive update message when current_version matches target_version", %{
      user: user,
      tmp_dir: tmp_dir
    } do
      {device, firmware} =
        device_fixture(tmp_dir, user, %{identifier: @valid_serial, product: @valid_product})

      Fixtures.device_certificate_fixture(device)

      query_uuid = firmware.uuid

      subscribe_for_updates(device)

      {:ok, socket} = SocketClient.start_link(@socket_config)
      SocketClient.join_and_wait(socket)

      assert_online_and_available(device)

      device = Repo.preload(device, :org)

      updated_device =
        Devices.get_device_by_identifier(device.org, device.identifier)
        |> elem(1)
        |> Repo.preload(:org)

      assert updated_device.firmware_metadata.uuid == query_uuid

      assert_connection_change()

      %DeviceConnection{last_seen_at: last_seen_at} =
        Connections.get_latest_for_device(updated_device.id)

      assert Time.diff(DateTime.utc_now(), last_seen_at) < 2

      close_socket_cleanly(socket)
    end

    test "removes device from deployment and sets reason if firmware doesn't match",
         %{
           user: user,
           tmp_dir: tmp_dir
         } do
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      firmware =
        Fixtures.firmware_fixture(org_key, product, %{
          version: "0.0.1",
          dir: tmp_dir
        })

      {:ok, deployment_group} =
        Fixtures.deployment_group_fixture(org, firmware, %{
          name: "Every Device",
          conditions: %{
            "version" => "<= 1.0.0",
            "tags" => ["beta", "beta-edge"]
          }
        })
        |> ManagedDeployments.update_deployment_group(%{is_active: true})

      device =
        Fixtures.device_fixture(
          org,
          product,
          firmware,
          %{
            deployment_id: deployment_group.id,
            tags: ["beta", "beta-edge"],
            identifier: @valid_serial,
            product: @valid_product
          }
        )

      assert device.deployment_id
      assert Repo.aggregate(AuditLog, :count) == 0

      Fixtures.device_certificate_fixture(device)

      subscribe_for_updates(device)

      {:ok, socket} = SocketClient.start_link(@socket_config)

      different_platform = "tester"

      SocketClient.join_and_wait(socket, %{
        "device_api_version" => "2.2.0",
        "nerves_fw_uuid" => Ecto.UUID.generate(),
        "nerves_fw_product" => "test",
        "nerves_fw_architecture" => device.firmware_metadata.architecture,
        "nerves_fw_platform" => different_platform,
        "nerves_fw_version" => "0.1.0"
      })

      assert_online_and_available(device)

      [log, _, _] = AuditLogs.logs_by(device)

      assert log.description ==
               "Device no longer matches deployment group Every Device's requirements because of mismatched platform"

      close_socket_cleanly(socket)
    end

    test "does nothing when device matches deployment conditions", %{
      user: user,
      tmp_dir: tmp_dir
    } do
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      firmware =
        Fixtures.firmware_fixture(org_key, product, %{
          version: "0.0.1",
          dir: tmp_dir
        })

      {:ok, deployment_group} =
        Fixtures.deployment_group_fixture(org, firmware, %{
          name: "a different name",
          conditions: %{
            "version" => "<= 1.0.0",
            "tags" => ["beta", "beta-edge"]
          }
        })
        |> ManagedDeployments.update_deployment_group(%{is_active: true})

      device =
        Fixtures.device_fixture(
          org,
          product,
          firmware,
          %{
            deployment_id: deployment_group.id,
            tags: ["beta", "beta-edge"],
            identifier: @valid_serial,
            product: @valid_product
          }
        )

      assert device.deployment_id

      Fixtures.device_certificate_fixture(device)

      subscribe_for_updates(device)

      {:ok, socket} = SocketClient.start_link(@socket_config)

      SocketClient.join_and_wait(socket, %{
        "nerves_fw_architecture" => device.firmware_metadata.architecture,
        "nerves_fw_platform" => device.firmware_metadata.platform,
        "nerves_fw_version" => "0.0.1"
      })

      assert_online_and_available(device)

      device = Repo.reload(device)
      assert device.deployment_id

      close_socket_cleanly(socket)
    end
  end

  describe "Custom CA Signers" do
    @describetag :tmp_dir

    test "valid certificate can connect", %{user: user, tmp_dir: tmp_dir} do
      org = Fixtures.org_fixture(user, %{name: "custom_ca_test"})
      {device, _firmware} = device_fixture(tmp_dir, user, %{identifier: @valid_serial}, org)

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

      subscribe_for_updates(device)

      {:ok, socket} = SocketClient.start_link(opts)
      SocketClient.join_and_wait(socket)

      assert_connection_change()
      assert_online_and_available(device)

      close_socket_cleanly(socket)
    end

    test "valid certificate expired signer can connect", %{user: user, tmp_dir: tmp_dir} do
      org = Fixtures.org_fixture(user, %{name: "custom_ca_test"})
      {device, _firmware} = device_fixture(tmp_dir, user, %{identifier: @valid_serial}, org)

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

      subscribe_for_updates(device)

      {:ok, socket} = SocketClient.start_link(opts)
      SocketClient.join_and_wait(socket)

      assert_connection_change()
      assert_online_and_available(device)

      close_socket_cleanly(socket)
    end

    test "ca signer last used is updated", %{user: user, tmp_dir: tmp_dir} do
      org = Fixtures.org_fixture(user, %{name: "ca_cert_is_updated"})

      {device, _firmware} = device_fixture(tmp_dir, user, %{identifier: @valid_serial}, org)

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

      subscribe_for_updates(device)

      {:ok, socket} = SocketClient.start_link(opts)
      SocketClient.join_and_wait(socket)
      assert_online_and_available(device)
      close_socket_cleanly(socket)

      {:ok, socket} = SocketClient.start_link(opts)
      SocketClient.join_and_wait(socket)

      assert_online_and_available(device)

      [%{last_used: updated_last_used}] = Devices.get_ca_certificates(org)

      assert last_used != updated_last_used

      close_socket_cleanly(socket)
    end
  end

  describe "archives" do
    @tag :tmp_dir
    test "on connect receive an archive", %{user: user, tmp_dir: tmp_dir} do
      org = Fixtures.org_fixture(user)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      product = Fixtures.product_fixture(user, org)

      firmware =
        Fixtures.firmware_fixture(org_key, product, %{
          version: "0.0.1",
          dir: tmp_dir
        })
        |> Repo.preload([:product])

      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      {:ok, deployment_group} =
        Fixtures.deployment_group_fixture(org, firmware, %{
          name: "beta",
          conditions: %{
            "version" => "<= 1.0.0",
            "tags" => ["beta"]
          },
          archive_id: archive.id
        })
        |> ManagedDeployments.update_deployment_group(%{is_active: true})

      device =
        Fixtures.device_fixture(
          org,
          product,
          firmware,
          %{
            tags: ["beta", "beta-edge"],
            identifier: @valid_serial,
            deployment_id: deployment_group.id
          }
        )

      Fixtures.device_certificate_fixture(device)

      subscribe_for_updates(device)

      {:ok, socket} = SocketClient.start_link(@socket_config)
      SocketClient.join_and_wait(socket, %{"device_api_version" => "2.0.0"})

      assert_connection_change()
      assert_online_and_available(device)

      archive = SocketClient.wait_archive(socket)
      assert %{"url" => _, "version" => _} = archive

      close_socket_cleanly(socket)
    end

    @tag :tmp_dir
    test "on updates enabled receive an archive", %{user: user, tmp_dir: tmp_dir} do
      org = Fixtures.org_fixture(user)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      product = Fixtures.product_fixture(user, org)

      firmware =
        Fixtures.firmware_fixture(org_key, product, %{
          version: "0.0.1",
          dir: tmp_dir
        })
        |> Repo.preload([:product])

      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      {:ok, deployment_group} =
        Fixtures.deployment_group_fixture(org, firmware, %{
          name: "beta",
          conditions: %{
            "version" => "<= 1.0.0",
            "tags" => ["beta"]
          },
          archive_id: archive.id
        })
        |> ManagedDeployments.update_deployment_group(%{is_active: true})

      device =
        Fixtures.device_fixture(
          org,
          product,
          firmware,
          %{
            tags: ["beta", "beta-edge"],
            identifier: @valid_serial,
            deployment_id: deployment_group.id
          }
        )

      Fixtures.device_certificate_fixture(device)

      subscribe_for_updates(device)

      {:ok, socket} = SocketClient.start_link(@socket_config)
      SocketClient.join_and_wait(socket, %{"device_api_version" => "2.0.0"})

      assert_connection_change()
      assert_online_and_available(device)

      archive = SocketClient.wait_archive(socket)
      assert %{"url" => _, "version" => _} = archive

      {:ok, device} = Devices.update_device(device, %{updates_enabled: false})
      {:ok, _device} = Devices.update_device(device, %{updates_enabled: true})

      archive = SocketClient.wait_archive(socket)
      assert %{"url" => _, "version" => _} = archive

      close_socket_cleanly(socket)
    end

    @tag :tmp_dir
    test "deployment archive updated", %{user: user, tmp_dir: tmp_dir} do
      org = Fixtures.org_fixture(user)
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      product = Fixtures.product_fixture(user, org)

      firmware =
        Fixtures.firmware_fixture(org_key, product, %{
          version: "0.0.1",
          dir: tmp_dir
        })
        |> Repo.preload([:product])

      {:ok, deployment_group} =
        Fixtures.deployment_group_fixture(org, firmware, %{
          name: "beta",
          conditions: %{
            "version" => "<= 1.0.0",
            "tags" => ["beta"]
          }
        })
        |> ManagedDeployments.update_deployment_group(%{is_active: true})

      device =
        Fixtures.device_fixture(
          org,
          product,
          firmware,
          %{
            tags: ["beta", "beta-edge"],
            identifier: @valid_serial,
            deployment_id: deployment_group.id
          }
        )

      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      Fixtures.device_certificate_fixture(device)

      subscribe_for_updates(device)

      {:ok, socket} = SocketClient.start_link(@socket_config)
      SocketClient.join_and_wait(socket, %{"device_api_version" => "2.0.0"})

      assert_connection_change()
      assert_online_and_available(device)

      {:ok, _deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{archive_id: archive.id})

      archive = SocketClient.wait_archive(socket)
      assert %{"url" => _, "version" => _} = archive

      close_socket_cleanly(socket)
    end
  end

  def close_socket_cleanly(socket) do
    SocketClient.clean_close(socket)
    eventually assert_connection_change()
    eventually(assert(Repo.all(where(DeviceConnection, status: :connected)) == []))
  end
end

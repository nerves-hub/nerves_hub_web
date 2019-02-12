defmodule NervesHubDeviceWeb.WebsocketTest do
  use ExUnit.Case
  use NervesHubDeviceWeb.ChannelCase
  alias NervesHubWebCore.Fixtures
  alias NervesHubWebCore.{Accounts, Deployments, Devices, Devices.Device, Repo}
  alias NervesHubDevice.Presence

  alias PhoenixClient.{Socket, Channel, Message}

  @valid_serial "device-1234"
  @valid_product "test-product"

  @fake_ssl_socket_config [
    url: "wss://127.0.0.1:4001/socket/websocket",
    json_library: Jason,
    reconnect_interval: 50,
    ssl_verify: :verify_peer,
    transport_opts: [
      socket_opts: [
        certfile: Path.expand("../../test/fixtures/ssl/device-fake.pem") |> to_charlist,
        keyfile: Path.expand("../../test/fixtures/ssl/device-fake-key.pem") |> to_charlist,
        cacertfile: Path.expand("../../test/fixtures/ssl/ca-fake.pem") |> to_charlist,
        server_name_indication: 'device.nerves-hub.org'
      ]
    ]
  ]

  @ssl_socket_config [
    url: "wss://127.0.0.1:4001/socket/websocket",
    json_library: Jason,
    reconnect_interval: 50,
    ssl_verify: :verify_peer,
    transport_opts: [
      socket_opts: [
        certfile: Path.expand("../../test/fixtures/ssl/device-1234-cert.pem") |> to_charlist,
        keyfile: Path.expand("../../test/fixtures/ssl/device-1234-key.pem") |> to_charlist,
        cacertfile: Path.expand("../../test/fixtures/ssl/ca.pem") |> to_charlist,
        server_name_indication: 'device.nerves-hub.org'
      ]
    ]
  ]

  def device_fixture(device_params \\ %{}, org \\ nil) do
    org = org || Fixtures.org_fixture()
    product = Fixtures.product_fixture(org)
    org_key = Fixtures.org_key_fixture(org)

    firmware =
      Fixtures.firmware_fixture(org_key, product, %{
        version: "0.0.1"
      })

    Fixtures.deployment_fixture(firmware)

    device =
      Fixtures.device_fixture(
        org,
        firmware,
        device_params |> Enum.into(%{tags: ["beta", "beta-edge"]})
      )

    {device, firmware}
  end

  describe "socket auth" do
    test "Can connect and authenticate to channel using client ssl certificate" do
      {device, firmware} =
        %{identifier: @valid_serial}
        |> device_fixture()

      Fixtures.device_certificate_fixture(device)
      {:ok, socket} = Socket.start_link(@ssl_socket_config)
      wait_for_socket(socket)
      {:ok, _reply, _channel} = Channel.join(socket, "firmware:#{firmware.uuid}")

      device =
        NervesHubWebCore.Repo.get(Device, device.id)
        |> NervesHubWebCore.Repo.preload(:org)

      assert Presence.device_status(device) == "online"
      refute_receive({"presence_diff", _})
      Socket.stop(socket)
    end

    test "authentication rejected to channel using incorrect client ssl certificate" do
      {:ok, socket} = Socket.start_link(@fake_ssl_socket_config)
      refute Socket.connected?(socket)
      Socket.stop(socket)
    end
  end

  describe "channel auth" do
    test "Cannot connect and authenticate to channel with non-matching serial" do
      {:ok, socket} = Socket.start_link(@ssl_socket_config)
      refute Socket.connected?(socket)
      Socket.stop(socket)
    end
  end

  describe "firmware update" do
    test "receives update message when eligible deployment is available" do
      {device, firmware} =
        %{identifier: @valid_serial}
        |> device_fixture()

      firmware = NervesHubWebCore.Repo.preload(firmware, :product)
      Fixtures.device_certificate_fixture(device)

      org = %Accounts.Org{id: device.org_id}
      org_key = Fixtures.org_key_fixture(org)

      firmware2 =
        Fixtures.firmware_fixture(org_key, firmware.product, %{
          version: "0.0.2"
        })

      Fixtures.deployment_fixture(firmware2, %{
        name: "a different name",
        conditions: %{
          "version" => ">=0.0.1",
          "tags" => ["beta", "beta-edge"]
        }
      })
      |> Deployments.update_deployment(%{is_active: true})

      {:ok, socket} = Socket.start_link(@ssl_socket_config)
      wait_for_socket(socket)
      {:ok, reply, _channel} = Channel.join(socket, "firmware:#{device.firmware_metadata.uuid}")
      assert %{"update_available" => true, "firmware_url" => _} = reply

      device =
        Device
        |> NervesHubWebCore.Repo.get(device.id)
        |> NervesHubWebCore.Repo.preload(:org)

      assert Presence.device_status(device) == "update pending"
      assert Time.diff(DateTime.utc_now(), device.last_communication) < 2
    end

    test "receives update message once deployment is available" do
      {device, firmware} =
        %{identifier: @valid_serial}
        |> device_fixture()

      device = NervesHubWebCore.Repo.preload(device, :org)
      firmware = NervesHubWebCore.Repo.preload(firmware, :product)

      Fixtures.device_certificate_fixture(device)
      org_key = Fixtures.org_key_fixture(device.org)
      target_uuid = firmware.uuid

      firmware =
        Fixtures.firmware_fixture(
          org_key,
          firmware.product,
          %{
            version: "0.0.2"
          }
        )

      deployment =
        Fixtures.deployment_fixture(firmware, %{
          name: "a different name",
          conditions: %{
            "version" => ">=0.0.1",
            "tags" => ["beta", "beta-edge"]
          }
        })

      {:ok, socket} = Socket.start_link(@ssl_socket_config)
      wait_for_socket(socket)
      Phoenix.PubSub.subscribe(NervesHubWeb.PubSub, "firmware:#{target_uuid}")
      {:ok, reply, _channel} = Channel.join(socket, "firmware:#{target_uuid}")
      assert %{"update_available" => false} = reply

      Deployments.update_deployment(deployment, %{is_active: true})
      device_id = device.id

      assert_receive(
        %Message{
          event: "update",
          payload: %{"device_id" => ^device_id, "firmware_url" => _f_url}
        },
        1000
      )
    end

    test "does not receive update message when current_version matches target_version" do
      {device, firmware} =
        %{identifier: @valid_serial, product: @valid_product}
        |> device_fixture()

      Fixtures.device_certificate_fixture(device)

      query_uuid = firmware.uuid

      {:ok, socket} = Socket.start_link(@ssl_socket_config)
      wait_for_socket(socket)
      {:ok, reply, _channel} = Channel.join(socket, "firmware:#{query_uuid}")
      assert %{"update_available" => false} = reply

      device = Repo.preload(device, :org)

      updated_device =
        Devices.get_device_by_identifier(device.org, device.identifier)
        |> elem(1)
        |> Repo.preload(:org)

      assert updated_device.firmware_metadata.uuid == query_uuid
      assert "online" == Presence.device_status(updated_device)
      assert Time.diff(DateTime.utc_now(), updated_device.last_communication) < 2
    end
  end

  describe "Custom CA Signers" do
    test "vaild certificate can connect" do
      org = Fixtures.org_fixture(%{name: "custom ca test"})

      {device, firmware} =
        %{identifier: @valid_serial}
        |> device_fixture(org)

      %{cert: ca, key: ca_key} = Fixtures.ca_certificate_fixture(org)

      key = X509.PrivateKey.new_ec(:secp256r1)

      cert =
        key
        |> X509.PublicKey.derive()
        |> X509.Certificate.new("CN=#{device.identifier}", ca, ca_key)

      nerves_hub_ca_cert =
        Path.expand("../../test/fixtures/ssl/ca.pem")
        |> File.read!()
        |> X509.Certificate.from_pem!()

      opts = [
        url: "wss://127.0.0.1:4001/socket/websocket",
        serializer: Jason,
        ssl_verify: :verify_peer,
        transport_opts: [
          socket_opts: [
            cert: X509.Certificate.to_der(cert),
            key: {:ECPrivateKey, X509.PrivateKey.to_der(key)},
            cacerts: [X509.Certificate.to_der(ca), X509.Certificate.to_der(nerves_hub_ca_cert)],
            server_name_indication: 'device.nerves-hub.org'
          ]
        ]
      ]

      {:ok, socket} = Socket.start_link(opts)
      wait_for_socket(socket)
      {:ok, _reply, _channel} = Channel.join(socket, "firmware:#{firmware.uuid}")

      device =
        NervesHubWebCore.Repo.get(Device, device.id)
        |> NervesHubWebCore.Repo.preload(:org)

      assert Presence.device_status(device) == "online"
      refute_receive({"presence_diff", _})
    end

    test "ca signer last used is updated" do
      org = Fixtures.org_fixture(%{name: "ca cert is updated"})

      {device, firmware} =
        %{identifier: @valid_serial}
        |> device_fixture(org)

      %{cert: ca, key: ca_key, db_cert: %{last_used: last_used}} =
        Fixtures.ca_certificate_fixture(org)

      key = X509.PrivateKey.new_ec(:secp256r1)

      cert =
        key
        |> X509.PublicKey.derive()
        |> X509.Certificate.new("CN=#{device.identifier}", ca, ca_key)

      nerves_hub_ca_cert =
        Path.expand("../../test/fixtures/ssl/ca.pem")
        |> File.read!()
        |> X509.Certificate.from_pem!()

      opts = [
        url: "wss://127.0.0.1:4001/socket/websocket",
        serializer: Jason,
        ssl_verify: :verify_peer,
        transport_opts: [
          socket_opts: [
            cert: X509.Certificate.to_der(cert),
            key: {:ECPrivateKey, X509.PrivateKey.to_der(key)},
            cacerts: [X509.Certificate.to_der(ca), X509.Certificate.to_der(nerves_hub_ca_cert)],
            server_name_indication: 'device.nerves-hub.org'
          ]
        ]
      ]

      {:ok, socket} = Socket.start_link(opts)
      wait_for_socket(socket)
      {:ok, _reply, channel} = Channel.join(socket, "firmware:#{firmware.uuid}")
      Channel.stop(channel)
      Socket.stop(socket)
      {:ok, socket} = Socket.start_link(opts)
      wait_for_socket(socket)
      {:ok, _reply, _channel} = Channel.join(socket, "firmware:#{firmware.uuid}")

      [%{last_used: updated_last_used}] = Devices.get_ca_certificates(org)

      assert last_used != updated_last_used
    end
  end

  def wait_for_socket(socket) do
    unless Socket.connected?(socket) do
      wait_for_socket(socket)
    end
  end
end

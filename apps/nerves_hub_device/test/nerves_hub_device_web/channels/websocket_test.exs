defmodule NervesHubDeviceWeb.WebsocketTest do
  use ExUnit.Case
  use NervesHubDeviceWeb.ChannelCase
  alias NervesHubWebCore.Fixtures
  alias NervesHubWebCore.{Accounts, Deployments, Devices, Devices.Device, Repo}
  alias NervesHubDevice.Presence
  alias NervesHubDeviceWeb.Endpoint

  alias PhoenixClient.{Socket, Channel}

  @valid_serial "device-1234"
  @valid_product "test-product"

  @device_port Application.get_env(:nerves_hub_device, Endpoint) |> get_in([:https, :port])

  @fake_ssl_socket_config [
    url: "wss://127.0.0.1:#{@device_port}/socket/websocket",
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
    url: "wss://127.0.0.1:#{@device_port}/socket/websocket",
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

  def device_fixture(user, device_params \\ %{}, org \\ nil) do
    org = org || Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org)

    firmware =
      Fixtures.firmware_fixture(org_key, product, %{
        version: "0.0.1"
      })

    Fixtures.deployment_fixture(org, firmware)

    params = Enum.into(device_params, %{tags: ["beta", "beta-edge"]})

    device =
      Fixtures.device_fixture(
        org,
        product,
        firmware,
        params
      )

    {device, firmware}
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
      {:ok, socket} = Socket.start_link(@ssl_socket_config)
      wait_for_socket(socket)
      {:ok, _reply, _channel} = Channel.join(socket, "device")

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

    test "Can connect and authenticate to channel using firmware topic", %{user: user} do
      {device, firmware} = device_fixture(user, %{identifier: @valid_serial})

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
  end

  describe "firmware update" do
    test "receives update message when eligible deployment is available", %{user: user} do
      {device, firmware} = device_fixture(user, %{identifier: @valid_serial})

      firmware = NervesHubWebCore.Repo.preload(firmware, :product)
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
          "version" => ">=0.0.1",
          "tags" => ["beta", "beta-edge"]
        }
      })
      |> Deployments.update_deployment(%{is_active: true})

      {:ok, socket} = Socket.start_link(@ssl_socket_config)
      wait_for_socket(socket)
      {:ok, reply, _channel} = Channel.join(socket, "device")
      assert %{"update_available" => true, "firmware_url" => _, "firmware_meta" => %{}} = reply

      device =
        Device
        |> NervesHubWebCore.Repo.get(device.id)
        |> NervesHubWebCore.Repo.preload(:org)

      assert Presence.device_status(device) == "update pending"
      assert Time.diff(DateTime.utc_now(), device.last_communication) < 2
    end

    test "receives update message once deployment is available", %{user: user} do
      {device, firmware} = device_fixture(user, %{identifier: @valid_serial})

      device = NervesHubWebCore.Repo.preload(device, :org)
      firmware = NervesHubWebCore.Repo.preload(firmware, :product)

      Fixtures.device_certificate_fixture(device)
      org_key = Fixtures.org_key_fixture(device.org)

      firmware2 =
        Fixtures.firmware_fixture(
          org_key,
          firmware.product,
          %{
            version: "0.0.2"
          }
        )

      Fixtures.firmware_delta_fixture(firmware, firmware2)

      deployment =
        Fixtures.deployment_fixture(device.org, firmware2, %{
          name: "a different name",
          conditions: %{
            "version" => ">=0.0.1",
            "tags" => ["beta", "beta-edge"]
          }
        })

      {:ok, socket} = Socket.start_link(@ssl_socket_config)
      wait_for_socket(socket)
      Phoenix.PubSub.subscribe(NervesHubWeb.PubSub, "device:#{device.id}")
      {:ok, reply, _channel} = Channel.join(socket, "device")
      assert %{"update_available" => false} = reply

      Deployments.update_deployment(deployment, %{is_active: true})

      assert_receive(
        %Phoenix.Socket.Broadcast{
          event: "update",
          payload: %{firmware_url: _f_url, firmware_meta: %{}}
        },
        1000
      )
    end

    test "does not receive update message when current_version matches target_version", %{
      user: user
    } do
      {device, firmware} =
        device_fixture(user, %{identifier: @valid_serial, product: @valid_product})

      Fixtures.device_certificate_fixture(device)

      query_uuid = firmware.uuid

      {:ok, socket} = Socket.start_link(@ssl_socket_config)
      wait_for_socket(socket)
      {:ok, reply, _channel} = Channel.join(socket, "device")
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
    test "vaild certificate can connect", %{user: user} do
      org = Fixtures.org_fixture(user, %{name: "custom_ca_test"})
      {device, _firmware} = device_fixture(user, %{identifier: @valid_serial}, org)

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
        url: "wss://127.0.0.1:#{@device_port}/socket/websocket",
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
      {:ok, _reply, _channel} = Channel.join(socket, "device")

      device =
        NervesHubWebCore.Repo.get(Device, device.id)
        |> NervesHubWebCore.Repo.preload(:org)

      assert Presence.device_status(device) == "online"
      refute_receive({"presence_diff", _})
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
        Path.expand("../../test/fixtures/ssl/ca.pem")
        |> File.read!()
        |> X509.Certificate.from_pem!()

      opts = [
        url: "wss://127.0.0.1:#{@device_port}/socket/websocket",
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

      :timer.sleep(2_000)

      {:ok, socket} = Socket.start_link(opts)
      wait_for_socket(socket)
      {:ok, _reply, _channel} = Channel.join(socket, "device")

      device =
        NervesHubWebCore.Repo.get(Device, device.id)
        |> NervesHubWebCore.Repo.preload(:org)

      assert Presence.device_status(device) == "online"
      refute_receive({"presence_diff", _})
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
        Path.expand("../../test/fixtures/ssl/ca.pem")
        |> File.read!()
        |> X509.Certificate.from_pem!()

      opts = [
        url: "wss://127.0.0.1:#{@device_port}/socket/websocket",
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
      {:ok, _reply, channel} = Channel.join(socket, "device")
      Channel.stop(channel)
      Socket.stop(socket)
      {:ok, socket} = Socket.start_link(opts)
      wait_for_socket(socket)
      {:ok, _reply, _channel} = Channel.join(socket, "device")

      [%{last_used: updated_last_used}] = Devices.get_ca_certificates(org)

      assert last_used != updated_last_used
    end
  end

  def wait_for_socket(_, _ \\ nil)

  def wait_for_socket(socket, nil) do
    timeout = 2_000
    {:ok, t_ref} = :timer.exit_after(timeout, "Timed out waiting for socket")
    wait_for_socket(socket, t_ref)
  end

  def wait_for_socket(socket, timer) do
    if Socket.connected?(socket) do
      :timer.cancel(timer)
    else
      wait_for_socket(socket, timer)
    end
  end
end

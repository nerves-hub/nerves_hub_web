defmodule NervesHubDeviceWeb.WebsocketTest do
  use ExUnit.Case
  use NervesHubDeviceWeb.ChannelCase
  alias NervesHubCore.Fixtures
  alias NervesHubCore.{Accounts, Deployments, Devices, Devices.Device, Repo}
  alias NervesHubDevice.Presence

  @valid_serial "device-1234"
  @valid_product "test-product"

  @fake_ssl_socket_config [
    url: "wss://127.0.0.1:4001/socket/websocket",
    serializer: Jason,
    ssl_verify: :verify_peer,
    socket_opts: [
      certfile: Path.expand("../../test/fixtures/cfssl/device-fake.pem") |> to_charlist,
      keyfile: Path.expand("../../test/fixtures/cfssl/device-fake-key.pem") |> to_charlist,
      cacertfile: Path.expand("../../test/fixtures/cfssl/ca-fake.pem") |> to_charlist,
      server_name_indication: 'device.nerves-hub.org'
    ]
  ]

  @ssl_socket_config [
    url: "wss://127.0.0.1:4001/socket/websocket",
    serializer: Jason,
    ssl_verify: :verify_peer,
    socket_opts: [
      certfile: Path.expand("../../test/fixtures/cfssl/device-1234-cert.pem") |> to_charlist,
      keyfile: Path.expand("../../test/fixtures/cfssl/device-1234-key.pem") |> to_charlist,
      cacertfile: Path.expand("../../test/fixtures/cfssl/ca.pem") |> to_charlist,
      server_name_indication: 'device.nerves-hub.org'
    ]
  ]

  def device_fixture(device_params \\ %{}) do
    org = Fixtures.org_fixture()
    product = Fixtures.product_fixture(org)
    org_key = Fixtures.org_key_fixture(org)

    firmware =
      Fixtures.firmware_fixture(org_key, product, %{
        version: "0.0.1"
      })

    deployment = Fixtures.deployment_fixture(firmware)

    device = Fixtures.device_fixture(org, firmware, deployment, device_params)
    Fixtures.device_certificate_fixture(device)

    {device, firmware}
  end

  defmodule ClientSocket do
    use PhoenixChannelClient.Socket

    def handle_close(reason, state) do
      send(state.opts[:caller], {:socket_closed, reason})
      {:noreply, state}
    end
  end

  defmodule ClientChannel do
    use PhoenixChannelClient
    require Logger

    def handle_in(event, payload, state) do
      send(state.opts[:caller], {event, payload})
      {:noreply, state}
    end

    def handle_reply(payload, state) do
      send(state.opts[:caller], payload)
      {:noreply, state}
    end

    def handle_close(payload, state) do
      send(state.opts[:caller], {:closed, payload})
      {:noreply, state}
    end
  end

  describe "socket auth" do
    test "Can connect and authenticate to channel using client ssl certificate" do
      {device, firmware} =
        %{identifier: @valid_serial}
        |> device_fixture()

      opts =
        @ssl_socket_config
        |> Keyword.put(:caller, self())

      {:ok, _} = ClientSocket.start_link(opts)

      {:ok, _channel} =
        ClientChannel.start_link(
          socket: ClientSocket,
          topic: "firmware:#{firmware.uuid}",
          caller: self()
        )

      ClientChannel.join(%{})

      assert_receive(
        {:ok, :join, %{"response" => %{}, "status" => "ok"}, _ref},
        1_000
      )

      device =
        NervesHubCore.Repo.get(Device, device.id)
        |> NervesHubCore.Repo.preload(:org)

      assert Presence.device_status(device) == "online"
      refute_receive({"presence_diff", _})
    end

    test "authentication rejected to channel using incorrect client ssl certificate" do
      opts =
        @fake_ssl_socket_config
        |> Keyword.put(:caller, self())

      {:ok, _} = ClientSocket.start_link(opts)

      {:ok, _channel} =
        ClientChannel.start_link(
          socket: ClientSocket,
          topic: "device:1234",
          caller: self()
        )

      ClientChannel.join()
      assert_receive({:socket_closed, {:tls_alert, 'unknown ca'}}, 1_000)
    end
  end

  describe "channel auth" do
    test "Cannot connect and authenticate to channel with non-matching serial" do
      {:ok, fake_uuid} = Ecto.UUID.bingenerate() |> Ecto.UUID.load()

      opts =
        @ssl_socket_config
        |> Keyword.put(:caller, self())

      {:ok, _} = ClientSocket.start_link(opts)

      {:ok, _channel} =
        ClientChannel.start_link(
          socket: ClientSocket,
          topic: "firmware:#{fake_uuid}",
          caller: self()
        )

      ClientChannel.join()

      assert_receive(
        {:socket_closed, {403, "Forbidden"}},
        1_000
      )
    end
  end

  describe "firmware update" do
    test "receives update message when eligible deployment is available" do
      {device, _firmware} =
        %{identifier: @valid_serial}
        |> device_fixture()

      device =
        device
        |> NervesHubCore.Repo.preload(last_known_firmware: [:product])

      org = %Accounts.Org{id: device.org_id}
      org_key = Fixtures.org_key_fixture(org, %{name: "another key"})

      firmware2 =
        Fixtures.firmware_fixture(org_key, device.last_known_firmware.product, %{
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

      opts =
        @ssl_socket_config
        |> Keyword.put(:caller, self())

      {:ok, _} = ClientSocket.start_link(opts)

      {:ok, _channel} =
        ClientChannel.start_link(
          socket: ClientSocket,
          topic: "firmware:#{device.last_known_firmware.uuid}",
          caller: self()
        )

      ClientChannel.join(%{})

      assert_receive(
        {:ok, :join,
         %{
           "response" => %{"update_available" => true, "firmware_url" => _},
           "status" => "ok"
         }, _ref},
        1_000
      )

      device = NervesHubCore.Repo.get(Devices.Device, device.id)

      device =
        Device
        |> NervesHubCore.Repo.get(device.id)
        |> NervesHubCore.Repo.preload(:org)

      assert Presence.device_status(device) == "update pending"
    end

    test "receives update message once deployment is available" do
      {device, firmware} =
        %{identifier: @valid_serial}
        |> device_fixture()

      target_uuid = firmware.uuid

      device =
        device
        |> NervesHubCore.Repo.preload(last_known_firmware: [:org_key, :product])

      firmware =
        Fixtures.firmware_fixture(
          device.last_known_firmware.org_key,
          device.last_known_firmware.product,
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

      {:ok, _} =
        @ssl_socket_config
        |> Keyword.put(:caller, self())
        |> ClientSocket.start_link()

      {:ok, _channel} =
        ClientChannel.start_link(
          socket: ClientSocket,
          topic: "firmware:#{target_uuid}",
          caller: self()
        )

      Phoenix.PubSub.subscribe(NervesHubWeb.PubSub, "firmware:#{target_uuid}")
      ClientChannel.join(%{})

      assert_receive(
        {:ok, :join, %{"response" => %{"update_available" => false}, "status" => "ok"}, _ref},
        1000
      )

      Deployments.update_deployment(deployment, %{is_active: true})
      device_id = device.id
      assert_receive({"update", %{"device_id" => ^device_id, "firmware_url" => _f_url}}, 1000)
    end

    test "does not receive update message when current_version matches target_version" do
      {device, firmware} =
        %{identifier: @valid_serial, product: @valid_product}
        |> device_fixture()

      query_uuid = firmware.uuid

      {:ok, _} =
        @ssl_socket_config
        |> Keyword.put(:caller, self())
        |> ClientSocket.start_link()

      {:ok, _channel} =
        ClientChannel.start_link(
          socket: ClientSocket,
          topic: "firmware:#{query_uuid}",
          caller: self()
        )

      ClientChannel.join(%{})

      assert_receive(
        {:ok, :join,
         %{
           "response" => %{"update_available" => false},
           "status" => "ok"
         }, _ref},
        1_000
      )

      device = Repo.preload(device, :org)

      updated_device =
        Devices.get_device_by_identifier(device.org, device.identifier)
        |> elem(1)
        |> Repo.preload(:org)

      assert updated_device.last_known_firmware.uuid == query_uuid
      assert "online" == Presence.device_status(updated_device)
    end
  end
end

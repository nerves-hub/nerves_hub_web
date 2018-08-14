defmodule NervesHubDeviceWeb.WebsocketTest do
  use ExUnit.Case, async: false
  use NervesHubDeviceWeb.ChannelCase
  alias NervesHubCore.Fixtures
  alias NervesHubCore.{Accounts, Deployments, Devices, Repo}
  alias NervesHubDeviceWeb.DeviceChannel

  @valid_serial "device-1234"
  @valid_product "test-product"
  @valid_firmware_url "http://foo.com/bar"

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

  def device_fixture(device_params \\ %{}, firmware_uuid \\ "foo") do
    org = Fixtures.org_fixture()
    product = Fixtures.product_fixture(org)
    org_key = Fixtures.org_key_fixture(org)

    firmware =
      Fixtures.firmware_fixture(org_key, product, %{
        uuid: firmware_uuid,
        version: "0.0.1",
        upload_metadata: %{"public_path" => @valid_firmware_url}
      })

    {:ok, deployment} =
      Fixtures.deployment_fixture(firmware)
      |> Deployments.update_deployment(%{is_active: true})

    device = Fixtures.device_fixture(org, firmware, deployment, device_params)
    Fixtures.device_certificate_fixture(device)
    device
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
      {:ok, target_uuid} = Ecto.UUID.bingenerate() |> Ecto.UUID.load()

      device =
        %{identifier: @valid_serial}
        |> device_fixture(target_uuid)

      opts =
        @ssl_socket_config
        |> Keyword.put(:caller, self())

      {:ok, _} = ClientSocket.start_link(opts)

      {:ok, _channel} =
        ClientChannel.start_link(
          socket: ClientSocket,
          topic: "device:#{target_uuid}",
          caller: self()
        )

      ClientChannel.join(%{})

      assert_receive(
        {:ok, :join, %{"response" => %{}, "status" => "ok"}, _ref},
        1_000
      )

      device = NervesHubCore.Repo.get(Devices.Device, device.id)
      assert DeviceChannel.online?(device)
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
          topic: "device:#{fake_uuid}",
          caller: self()
        )

      ClientChannel.join()

      assert_receive(
        {:socket_closed, {403, "Forbidden"}},
        1_000
      )
    end

    #   test "Cannot connect and authenticate to channel with non-existing serial" do
    #     opts =
    #       @ssl_socket_config
    #       |> Keyword.put(:caller, self())

    #     {:ok, _} = ClientSocket.start_link(opts)

    #     {:ok, _channel} =
    #       ClientChannel.start_link(
    #         socket: ClientSocket,
    #         topic: "device:#{@valid_serial}",
    #         caller: self()
    #       )

    #     ClientChannel.join()

    #     assert_receive(
    #       {:socket_closed, {403, "Forbidden"}},
    #       1_000
    #     )
    #   end
  end

  describe "firmware update" do
    test "receives update message when eligible deployment is available" do
      {:ok, target_uuid} = Ecto.UUID.bingenerate() |> Ecto.UUID.load()
      {:ok, not_target_uuid} = Ecto.UUID.bingenerate() |> Ecto.UUID.load()

      device =
        %{identifier: @valid_serial}
        |> device_fixture(target_uuid)

      org = %Accounts.Org{id: device.org_id}
      product = Fixtures.product_fixture(org, %{name: "new product"})
      org_key = Fixtures.org_key_fixture(org, %{name: "another key"})

      firmware =
        Fixtures.firmware_fixture(org_key, product, %{
          uuid: not_target_uuid,
          version: "0.0.2",
          upload_metadata: %{"public_path" => @valid_firmware_url}
        })

      Fixtures.deployment_fixture(firmware, %{
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
          topic: "device:#{target_uuid}",
          caller: self()
        )

      ClientChannel.join(%{})

      assert_receive(
        {:ok, :join,
         %{
           "response" => %{"update_available" => true, "firmware_url" => @valid_firmware_url},
           "status" => "ok"
         }, _ref},
        1_000
      )

      device = NervesHubCore.Repo.get(Devices.Device, device.id)
      assert DeviceChannel.update_pending?(device)
    end

    test "does not receive update message when current_version matches target_version" do
      {:ok, query_uuid} = Ecto.UUID.bingenerate() |> Ecto.UUID.load()

      device =
        %{identifier: @valid_serial, product: @valid_product}
        |> device_fixture(query_uuid)

      opts =
        @ssl_socket_config
        |> Keyword.put(:caller, self())

      {:ok, _} = ClientSocket.start_link(opts)

      {:ok, _channel} =
        ClientChannel.start_link(
          socket: ClientSocket,
          topic: "device:#{query_uuid}",
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
        |> Repo.preload(:last_known_firmware)

      assert updated_device.last_known_firmware.uuid == query_uuid
      refute DeviceChannel.update_pending?(device)
    end
  end
end

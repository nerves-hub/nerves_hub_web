defmodule NervesHub.Integration.WebsocketTest do
  use ExUnit.Case, async: false
  use NervesHubWeb.ChannelCase
  alias NervesHub.Fixtures
  alias NervesHub.Devices

  @serial_header Application.get_env(:nerves_hub, :device_serial_header)
  @valid_serial "device-1234"

  @fake_ssl_socket_config [
    url: "wss://127.0.0.1:4003/socket/websocket",
    serializer: Jason,
    ssl_verify: :verify_peer,
    socket_opts: [
      certfile: Path.expand("test/fixtures/certs/device-fake.pem") |> to_charlist,
      keyfile: Path.expand("test/fixtures/certs/device-fake-key.pem") |> to_charlist,
      cacertfile: Path.expand("test/fixtures/certs/ca-fake.pem") |> to_charlist,
      server_name_indication: 'nerves-hub'
    ]
  ]

  @ssl_socket_config [
    url: "wss://127.0.0.1:4003/socket/websocket",
    serializer: Jason,
    ssl_verify: :verify_peer,
    socket_opts: [
      certfile: Path.expand("test/fixtures/certs/device-1234.pem") |> to_charlist,
      keyfile: Path.expand("test/fixtures/certs/device-1234-key.pem") |> to_charlist,
      cacertfile: Path.expand("test/fixtures/certs/ca.pem") |> to_charlist,
      server_name_indication: 'nerves-hub'
    ]
  ]

  @proxy_socket_config [
    url: "wss://127.0.0.1:4003/socket/websocket",
    serializer: Jason,
    extra_headers: [{@serial_header, @valid_serial}],
    socket_opts: [
      server_name_indication: 'nerves-hub'
    ]
  ]

  def device_fixture(device_params \\ %{}) do
    tenant = Fixtures.tenant_fixture()
    tenant_key = Fixtures.tenant_key_fixture(tenant)
    firmware = Fixtures.firmware_fixture(tenant, tenant_key)
    deployment = Fixtures.deployment_fixture(tenant, firmware)
    Fixtures.device_fixture(tenant, firmware, deployment, device_params)
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
      device =
        %{identifier: @valid_serial}
        |> device_fixture()

      opts =
        @ssl_socket_config
        |> Keyword.put(:caller, self())

      {:ok, _} = ClientSocket.start_link(opts)

      {:ok, _channel} =
        ClientChannel.start_link(
          socket: ClientSocket,
          topic: "device:#{device.identifier}",
          caller: self()
        )

      ClientChannel.join(%{"version" => "0.0.1"})

      assert_receive(
        {:ok, :join, %{"response" => %{}, "status" => "ok"}, _ref},
        1_000
      )
    end

    test "authentication rejected to channel using incorrect client ssl certificate" do
      opts =
        @fake_ssl_socket_config
        |> Keyword.put(:caller, self())

      {:ok, _} = ClientSocket.start_link(opts)

      {:ok, _channel} =
        ClientChannel.start_link(
          socket: ClientSocket,
          topic: "device:#{@valid_serial}",
          caller: self()
        )

      ClientChannel.join()
      assert_receive({:socket_closed, {:tls_alert, 'unknown ca'}}, 1_000)
    end

    test "Can connect and authenticate to channel using proxy headers" do
      device = device_fixture()

      opts =
        @proxy_socket_config
        |> Keyword.put(:caller, self())

      {:ok, _} = ClientSocket.start_link(opts)

      {:ok, _channel} =
        ClientChannel.start_link(
          socket: ClientSocket,
          topic: "device:#{device.identifier}",
          caller: self()
        )

      ClientChannel.join(%{"version" => "0.1.1"})

      assert_receive(
        {:ok, :join, %{"response" => %{}, "status" => "ok"}, _ref},
        1_000
      )
    end
  end

  describe "channel auth" do
    test "Cannot connect and authenticate to channel with non-matching serial" do
      opts =
        @ssl_socket_config
        |> Keyword.put(:caller, self())

      {:ok, _} = ClientSocket.start_link(opts)

      {:ok, _channel} =
        ClientChannel.start_link(
          socket: ClientSocket,
          topic: "device:not_valid_serial",
          caller: self()
        )

      ClientChannel.join()

      assert_receive(
        {:error, :join, %{"response" => %{"reason" => "unauthorized"}, "status" => "error"},
         _ref},
        1_000
      )
    end

    test "Cannot connect and authenticate to channel with non-existing serial" do
      opts =
        @ssl_socket_config
        |> Keyword.put(:caller, self())

      {:ok, _} = ClientSocket.start_link(opts)

      {:ok, _channel} =
        ClientChannel.start_link(
          socket: ClientSocket,
          topic: "device:#{@valid_serial}",
          caller: self()
        )

      ClientChannel.join()

      assert_receive(
        {:error, :join, %{"response" => %{"reason" => "unauthorized"}, "status" => "error"},
         _ref},
        1_000
      )
    end
  end

  describe "firmware update" do
    test "receives update message when current_version does not match target_version" do
      device =
        %{identifier: @valid_serial, current_version: "a", target_version: "b"}
        |> device_fixture()

      opts =
        @ssl_socket_config
        |> Keyword.put(:caller, self())

      {:ok, _} = ClientSocket.start_link(opts)

      {:ok, _channel} =
        ClientChannel.start_link(
          socket: ClientSocket,
          topic: "device:#{device.identifier}",
          caller: self()
        )

      ClientChannel.join(%{"version" => device.current_version})

      assert_receive(
        {:ok, :join,
         %{
           "response" => %{"update_available" => true},
           "status" => "ok"
         }, _ref},
        1_000
      )
    end

    test "does not receive update message when current_version matches target_version" do
      device =
        %{identifier: @valid_serial, current_version: "a", target_version: "b"}
        |> device_fixture()

      opts =
        @ssl_socket_config
        |> Keyword.put(:caller, self())

      {:ok, _} = ClientSocket.start_link(opts)

      {:ok, _channel} =
        ClientChannel.start_link(
          socket: ClientSocket,
          topic: "device:#{device.identifier}",
          caller: self()
        )

      ClientChannel.join(%{"version" => device.target_version})

      assert_receive(
        {:ok, :join,
         %{
           "response" => %{"update_available" => false},
           "status" => "ok"
         }, _ref},
        1_000
      )

      {:ok, updated_device} = Devices.get_device_by_identifier(device.identifier)

      assert updated_device.current_version == device.target_version
    end
  end
end

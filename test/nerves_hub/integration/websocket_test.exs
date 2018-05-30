defmodule NervesHub.Integration.WebsocketTest do
  use ExUnit.Case, async: false

  @serial_header Application.get_env(:nerves_hub, :device_serial_header)

  @fake_ssl_socket_config [
    url: "wss://127.0.0.1:4003/socket/websocket",
    serializer: Jason,
    ssl_verify: :verify_peer,
    socket_opts: [
      certfile: Path.expand("test/fixtures/certs/device-fake.pem") |> to_charlist,
      keyfile: Path.expand("test/fixtures/certs/device-fake-key.pem") |> to_charlist,
      cacertfile: Path.expand("test/fixtures/certs/ca-fake.pem") |> to_charlist,
      server_name_indication: 'nerveshub'
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
      server_name_indication: 'nerveshub'
    ]
  ]

  @proxy_socket_config [
    url: "wss://127.0.0.1:4003/socket/websocket",
    serializer: Jason,
    extra_headers: [{@serial_header, "device-1234"}]
  ]

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

  test "Can connect and authenticate to channel using client ssl certificate" do
    opts =
      @ssl_socket_config
      |> Keyword.put(:caller, self())

    {:ok, _} = ClientSocket.start_link(opts)

    {:ok, _channel} =
      ClientChannel.start_link(socket: ClientSocket, topic: "device:lobby", caller: self())

    ClientChannel.join()

    assert_receive(
      {:ok, :join, %{"response" => %{"serial" => "device-1234"}, "status" => "ok"}, _ref},
      1_000
    )
  end

  test "authentication rejected to channel using incorrect client ssl certificate" do
    opts =
      @fake_ssl_socket_config
      |> Keyword.put(:caller, self())

    {:ok, _} = ClientSocket.start_link(opts)

    {:ok, _channel} =
      ClientChannel.start_link(socket: ClientSocket, topic: "device:lobby", caller: self())

    ClientChannel.join()
    assert_receive({:socket_closed, {:tls_alert, 'unknown ca'}}, 1_000)
  end

  test "Can connect and authenticate to channel using proxy headers" do
    opts =
      @proxy_socket_config
      |> Keyword.put(:caller, self())

    {:ok, _} = ClientSocket.start_link(opts)

    {:ok, _channel} =
      ClientChannel.start_link(socket: ClientSocket, topic: "device:lobby", caller: self())

    ClientChannel.join()

    assert_receive(
      {:ok, :join, %{"response" => %{"serial" => "device-1234"}, "status" => "ok"}, _ref},
      1_000
    )
  end
end

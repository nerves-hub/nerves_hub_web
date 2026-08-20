defmodule NervesHubWeb.DeviceSocketRedirectTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.Helpers.WebsocketConnectionError
  alias NervesHubWeb.DeviceEndpoint
  alias NervesHubWeb.DeviceSocket
  alias NervesHubWeb.Endpoint

  @web_port Application.compile_env(:nerves_hub, Endpoint) |> get_in([:http, :port])

  setup do
    devices_websocket_url = Application.get_env(:nerves_hub, :devices_websocket_url)
    redirect? = Application.get_env(:nerves_hub, :redirect_to_devices_websocket_url)

    on_exit(fn ->
      Application.put_env(:nerves_hub, :devices_websocket_url, devices_websocket_url)
      Application.put_env(:nerves_hub, :redirect_to_devices_websocket_url, redirect?)
    end)

    :ok
  end

  defp enable_redirect(host \\ "devices.nervescloud.com") do
    Application.put_env(:nerves_hub, :devices_websocket_url, host)
    Application.put_env(:nerves_hub, :redirect_to_devices_websocket_url, true)
  end

  describe "connect/3" do
    test "asks devices on the management endpoint to redirect when enabled" do
      enable_redirect()

      socket = %Phoenix.Socket{endpoint: Endpoint}

      assert {:error, {:redirect, "devices.nervescloud.com"}} =
               DeviceSocket.connect(%{}, socket, %{})
    end

    test "does not redirect when the flag is disabled" do
      Application.put_env(:nerves_hub, :devices_websocket_url, "devices.nervescloud.com")
      Application.put_env(:nerves_hub, :redirect_to_devices_websocket_url, false)

      socket = %Phoenix.Socket{endpoint: Endpoint}

      assert {:error, :no_auth} = DeviceSocket.connect(%{}, socket, %{})
    end

    test "never redirects the device endpoint, which is the destination" do
      enable_redirect()

      socket = %Phoenix.Socket{endpoint: DeviceEndpoint}

      assert {:error, :no_auth} = DeviceSocket.connect(%{}, socket, %{})
    end
  end

  describe "handle_error/2" do
    test "answers with a 301 to the device websocket host" do
      conn =
        Plug.Test.conn(:get, "/device-socket/websocket?vsn=2.0.0")
        |> WebsocketConnectionError.handle_error({:redirect, "devices.nervescloud.com"})

      assert conn.status == 301

      assert Plug.Conn.get_resp_header(conn, "location") == [
               "wss://devices.nervescloud.com/device-socket/websocket?vsn=2.0.0"
             ]
    end

    test "tolerates a full url in the config" do
      conn =
        Plug.Test.conn(:get, "/device-socket/websocket")
        |> WebsocketConnectionError.handle_error({:redirect, "wss://devices.nervescloud.com"})

      assert Plug.Conn.get_resp_header(conn, "location") == [
               "wss://devices.nervescloud.com/device-socket/websocket"
             ]
    end
  end

  describe "over a real connection" do
    test "the management endpoint redirects a device socket upgrade" do
      enable_redirect()

      {:ok, conn} = Mint.HTTP.connect(:http, "127.0.0.1", @web_port)

      headers = [
        {"upgrade", "websocket"},
        {"connection", "upgrade"},
        {"sec-websocket-version", "13"},
        {"sec-websocket-key", Base.encode64(:crypto.strong_rand_bytes(16))}
      ]

      {:ok, conn, _ref} = Mint.HTTP.request(conn, "GET", "/device-socket/websocket?vsn=2.0.0", headers, nil)

      {status, resp_headers} = receive_response(conn)

      assert status == 301

      assert {_, "wss://devices.nervescloud.com/device-socket/websocket?vsn=2.0.0"} =
               List.keyfind(resp_headers, "location", 0)
    end
  end

  defp receive_response(conn, status \\ nil, headers \\ []) do
    receive do
      message ->
        case Mint.HTTP.stream(conn, message) do
          {:ok, conn, responses} ->
            status =
              Enum.find_value(responses, status, fn
                {:status, _ref, code} -> code
                _ -> nil
              end)

            headers =
              Enum.reduce(responses, headers, fn
                {:headers, _ref, hs}, acc -> acc ++ hs
                _, acc -> acc
              end)

            if status && headers != [] do
              {status, headers}
            else
              receive_response(conn, status, headers)
            end

          {:error, _conn, error, _responses} ->
            flunk("request failed: #{inspect(error)}")
        end
    after
      5_000 -> flunk("timed out waiting for a response")
    end
  end
end

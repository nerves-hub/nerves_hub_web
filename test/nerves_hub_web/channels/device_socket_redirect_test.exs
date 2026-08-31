defmodule NervesHubWeb.DeviceSocketRedirectTest do
  use NervesHub.DataCase, async: false

  import ExUnit.CaptureLog

  alias NervesHub.Fixtures
  alias NervesHub.Helpers.WebsocketConnectionError
  alias NervesHub.ProductNotifications
  alias NervesHub.Products
  alias NervesHub.Products.Notification
  alias NervesHub.Support.Utils
  alias NervesHubWeb.Endpoint
  alias Phoenix.Socket.Broadcast

  require Logger

  @web_port Application.compile_env(:nerves_hub, Endpoint) |> get_in([:http, :port])

  setup do
    devices_websocket_url = Application.get_env(:nerves_hub, :devices_websocket_url)
    redirect? = Application.get_env(:nerves_hub, :redirect_to_devices_websocket_url)

    Application.put_env(:nerves_hub, NervesHubWeb.DeviceSocket, shared_secrets: [enabled: true])

    on_exit(fn ->
      Application.put_env(:nerves_hub, :devices_websocket_url, devices_websocket_url)
      Application.put_env(:nerves_hub, :redirect_to_devices_websocket_url, redirect?)
      Application.put_env(:nerves_hub, NervesHubWeb.DeviceSocket, shared_secrets: [enabled: false])
    end)

    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    {:ok, auth} = Products.create_shared_secret_auth(product)

    %{product: product, auth: auth}
  end

  defp enable_redirect(host \\ "devices.nervescloud.com") do
    Application.put_env(:nerves_hub, :devices_websocket_url, host)
    Application.put_env(:nerves_hub, :redirect_to_devices_websocket_url, true)
  end

  defp disable_redirect() do
    Application.put_env(:nerves_hub, :devices_websocket_url, "devices.nervescloud.com")
    Application.put_env(:nerves_hub, :redirect_to_devices_websocket_url, false)
  end

  # Connects to the management endpoint the way a misconfigured device would,
  # and answers with the pre-upgrade HTTP response.
  defp connect_to_management_endpoint(auth, identifier) do
    {:ok, conn} = Mint.HTTP.connect(:http, "127.0.0.1", @web_port)

    headers =
      [
        {"upgrade", "websocket"},
        {"connection", "upgrade"},
        {"sec-websocket-version", "13"},
        {"sec-websocket-key", Base.encode64(:crypto.strong_rand_bytes(16))}
      ] ++ Utils.nh1_key_secret_headers(auth, identifier)

    {:ok, conn, _ref} = Mint.HTTP.request(conn, "GET", "/device-socket/websocket?vsn=2.0.0", headers, nil)

    receive_response(conn)
  end

  describe "when the redirect is enabled" do
    test "a device is redirected to the device websocket host", %{auth: auth} do
      enable_redirect()

      {status, headers} = connect_to_management_endpoint(auth, Ecto.UUID.generate())

      assert status == 301

      assert {_, "wss://devices.nervescloud.com/device-socket/websocket?vsn=2.0.0"} =
               List.keyfind(headers, "location", 0)
    end

    test "a notification is raised against the product", %{auth: auth, product: product} do
      enable_redirect()

      identifier = Ecto.UUID.generate()

      {301, _headers} = connect_to_management_endpoint(auth, identifier)

      assert [notification] = Repo.all(Notification)

      assert notification.product_id == product.id
      assert notification.title == "A device connected to the wrong host."
      assert notification.message =~ identifier
      assert notification.message =~ "devices.nervescloud.com"
      assert notification.level == :warning
      assert notification.event_key == "wrong_websocket_host-#{identifier}"
      assert notification.metadata == %{"identifier" => identifier, "host" => "devices.nervescloud.com"}
    end

    test "each misconfigured device gets its own notification", %{auth: auth} do
      enable_redirect()

      {301, _} = connect_to_management_endpoint(auth, "device-a")
      {301, _} = connect_to_management_endpoint(auth, "device-b")

      assert Repo.all(Notification) |> length() == 2
    end

    test "a device reconnecting bumps the count rather than adding a row", %{auth: auth} do
      enable_redirect()

      {301, _} = connect_to_management_endpoint(auth, "device-a")
      {301, _} = connect_to_management_endpoint(auth, "device-a")
      {301, _} = connect_to_management_endpoint(auth, "device-a")

      assert [notification] = Repo.all(Notification)
      assert notification.occurrence_count == 3
    end

    test "each occurrence is broadcast, so an open page keeps counting up", %{auth: auth, product: product} do
      enable_redirect()

      ProductNotifications.subscribe(product.id)

      {301, _} = connect_to_management_endpoint(auth, "device-a")
      assert_receive %Broadcast{event: "created"}

      {301, _} = connect_to_management_endpoint(auth, "device-a")
      assert_receive %Broadcast{event: "created"}
    end

    test "the redirect is logged", %{auth: auth} do
      enable_redirect()

      # config/test.exs pins the logger to :warning, and this is an info log.
      level = Logger.level()
      Logger.configure(level: :info)
      on_exit(fn -> Logger.configure(level: level) end)

      log =
        capture_log(fn ->
          {301, _} = connect_to_management_endpoint(auth, Ecto.UUID.generate())
        end)

      assert log =~ "Device connected to the wrong host, redirecting"
    end

    test "the redirect reports telemetry naming the device and product", %{
      auth: auth,
      product: product
    } do
      enable_redirect()

      event = [:nerves_hub, :devices, :wrong_websocket_host]
      test_pid = self()

      :telemetry.attach(
        "wrong-websocket-host-test",
        event,
        fn ^event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach("wrong-websocket-host-test") end)

      identifier = Ecto.UUID.generate()

      {301, _} = connect_to_management_endpoint(auth, identifier)

      assert_receive {:telemetry, %{count: 1}, metadata}

      assert metadata.device_identifier == identifier
      assert metadata.product_id == product.id
      assert metadata.host == "devices.nervescloud.com"
      assert is_integer(metadata.device_id)
    end

    test "an unset device websocket host means no redirect", %{auth: auth} do
      Application.put_env(:nerves_hub, :redirect_to_devices_websocket_url, true)
      Application.put_env(:nerves_hub, :devices_websocket_url, nil)

      {status, _headers} = connect_to_management_endpoint(auth, Ecto.UUID.generate())

      assert status == 101
      assert Repo.all(Notification) == []
    end
  end

  describe "when the redirect is disabled" do
    test "the device connects as usual and no notification is raised", %{auth: auth} do
      disable_redirect()

      {status, _headers} = connect_to_management_endpoint(auth, Ecto.UUID.generate())

      assert status == 101
      assert Repo.all(Notification) == []
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

  # Reads the pre-upgrade HTTP response. Messages that aren't ours -- a pubsub
  # broadcast a test is waiting on, say -- are put back in the mailbox.
  defp receive_response(conn, status \\ nil, headers \\ [], stashed \\ []) do
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
              Enum.each(Enum.reverse(stashed), &send(self(), &1))
              {status, headers}
            else
              receive_response(conn, status, headers, stashed)
            end

          {:error, _conn, error, _responses} ->
            flunk("request failed: #{inspect(error)}")

          :unknown ->
            receive_response(conn, status, headers, [message | stashed])
        end
    after
      5_000 -> flunk("timed out waiting for a response")
    end
  end
end

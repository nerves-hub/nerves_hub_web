defmodule NervesHubDeviceWeb.ConsoleChannelTest do
  use NervesHubDeviceWeb.ChannelCase

  alias NervesHubDeviceWeb.{ConsoleChannel, Endpoint, UserSocket}
  alias NervesHubWebCore.Fixtures
  alias Phoenix.Socket.Broadcast

  setup do
    Fixtures.standard_fixture()
    |> connect_device()
  end

  describe "handle_in" do
    test "get_line", %{socket: socket} do
      payload = %{"data" => "test"}

      push(socket, "get_line", payload)
      assert_broadcast("get_line", ^payload)
    end

    test "init_attempt - broacast failure", %{socket: socket} do
      payload = %{"success" => false, "message" => "init failed"}

      push(socket, "init_attempt", payload)
      assert_broadcast("init_failure", ^payload)
    end

    test "init_attempt - no broadcast on success", %{socket: socket} do
      payload = %{"success" => true}
      push(socket, "init_attempt", payload)
      refute_broadcast("init_failure", ^payload)
    end

    test "put_chars", %{socket: socket} do
      payload = %{"data" => "test"}

      push(socket, "put_chars", payload)
      assert_broadcast("put_chars", ^payload)
    end
  end

  describe "broadcasts received" do
    test "ignores add_line broadcast", %{socket: socket} do
      assert ConsoleChannel.handle_info(%Broadcast{event: "add_line"}, socket) ==
               {:noreply, socket}

      refute_push("add_line", %{})
    end

    test "ignores phx_leave broadcast", %{socket: socket} do
      assert ConsoleChannel.handle_info(%Broadcast{event: "phx_leave"}, socket) ==
               {:noreply, socket}

      refute_push("phx_leave", %{})
    end

    test "pushes all other broadcasts to device", %{socket: socket} do
      broadcast_from(socket, "howdy", %{})
      assert_push("howdy", %{})
    end
  end

  defp connect_device(%{device: device, device_certificate: device_certificate}) do
    {:ok, _, socket} =
      UserSocket
      |> socket("device_socket:#{device.id}", %{
        certificate: device_certificate
      })
      |> Map.put(:endpoint, Endpoint)
      |> subscribe_and_join(ConsoleChannel, "console")

    socket.endpoint.subscribe("console:#{device.id}")

    Process.unlink(socket.channel_pid)
    %{device: device, socket: socket}
  end
end

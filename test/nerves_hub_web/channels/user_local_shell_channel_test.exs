defmodule NervesHubWeb.UserLocalShellChannelTest do
  use NervesHubWeb.ChannelCase

  alias NervesHub.Accounts
  alias NervesHub.Extensions
  alias NervesHub.Extensions.LocalShell
  alias NervesHub.Fixtures
  alias NervesHubWeb.APISocket
  alias NervesHubWeb.UserLocalShellChannel
  alias Phoenix.Socket.Broadcast

  describe "API Token : join/3" do
    test "authorized users can join the device channel", %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()

      device = device_fixture(user, %{identifier: "test-device-123"}, tmp_dir)

      user_token = Accounts.create_user_api_token(user, "test-token")

      {:ok, socket} = connect(APISocket, %{"token" => user_token})

      assert {:ok, _reply, _channel} =
               subscribe_and_join(
                 socket,
                 UserLocalShellChannel,
                 "user:local_shell:identifier-#{device.identifier}"
               )
    end

    test "unauthorized user cannot join the device channel", %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      other_user = Fixtures.user_fixture()

      device = device_fixture(user, %{identifier: "test-device-123"}, tmp_dir)

      other_user_token = Accounts.create_user_api_token(other_user, "test-token")

      {:ok, socket} = connect(APISocket, %{"token" => other_user_token})

      assert {:error, %{reason: _reason}} =
               subscribe_and_join(
                 socket,
                 UserLocalShellChannel,
                 "user:local_shell:identifier-#{device.identifier}"
               )
    end
  end

  describe "handle_in" do
    setup %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      device = device_fixture(user, %{identifier: "shell-test-device"}, tmp_dir)
      user_token = Accounts.create_user_api_token(user, "test-token")
      {:ok, socket} = connect(APISocket, %{"token" => user_token})

      {:ok, _reply, channel} =
        subscribe_and_join(
          socket,
          UserLocalShellChannel,
          "user:local_shell:identifier-#{device.identifier}"
        )

      # Standing in for the device's extensions channel.
      :ok = Extensions.PubSub.subscribe_device(device.id)

      %{channel: channel}
    end

    test "input reaches the device's extensions channel", %{channel: channel} do
      push(channel, "input", %{"data" => "\r"})

      assert_receive %Broadcast{event: "local_shell:shell_input", payload: %{"data" => "\r"}}, 500
    end

    test "window size reaches the device's extensions channel", %{channel: channel} do
      push(channel, "window_size", %{"cols" => 80, "rows" => 24})

      assert_receive %Broadcast{event: "local_shell:window_size", payload: %{"cols" => 80, "rows" => 24}}, 500
    end
  end

  describe "connecting" do
    test "joining asks the device's local shell to connect", %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      device = device_fixture(user, %{identifier: "shell-connect-device"}, tmp_dir)
      user_token = Accounts.create_user_api_token(user, "test-token")
      {:ok, socket} = connect(APISocket, %{"token" => user_token})

      :ok = Extensions.PubSub.subscribe_device(device.id)

      {:ok, _reply, channel} =
        subscribe_and_join(socket, UserLocalShellChannel, "user:local_shell:identifier-#{device.identifier}")

      # Tagged with the module, so the extensions channel hands it to the shell.
      assert_receive {LocalShell, {:connect, pid}}, 500
      assert pid == channel.channel_pid
    end
  end

  defp device_fixture(user, device_params, tmp_dir) do
    org = Fixtures.org_fixture(user)
    {:ok, org_user} = Accounts.get_org_user(org, user)
    {:ok, _updated_org_user} = Accounts.change_org_user_role(org_user, :manage)

    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

    firmware =
      Fixtures.firmware_fixture(org_key, product, %{
        version: "0.0.1",
        dir: tmp_dir
      })

    Fixtures.device_fixture(
      org,
      product,
      firmware,
      device_params
    )
  end
end

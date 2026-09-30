defmodule NervesHubWeb.Extensions.AlarmsTest do
  @moduledoc """
  The alarms extension end to end, through a real device socket: the handshake,
  the sync the platform asks for on attach, and events after it.
  """

  use NervesHubWeb.ChannelCase
  use DefaultMocks

  alias NervesHub.Devices.Alarms
  alias NervesHub.Fixtures
  alias NervesHubWeb.DeviceChannel
  alias NervesHubWeb.DeviceSocket
  alias NervesHubWeb.ExtensionsChannel

  defp connect_device(tmp_dir, product_extensions) do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org, %{extensions: product_extensions})
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{version: "0.0.1", dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)
    %{db_cert: certificate} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} = connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    params = %{"device_api_version" => "2.2.0"}
    {:ok, _, _device_channel} = subscribe_and_join(socket, DeviceChannel, "device:#{device.id}", params)
    assert_push("extensions:get", _)

    {socket, device}
  end

  defp join_extensions(socket, extension_versions) do
    params = Map.merge(%{"device_api_version" => "2.2.0"}, extension_versions)
    subscribe_and_join(socket, ExtensionsChannel, "extensions", params)
  end

  # Pushes are handled in order by the channel process, so once it has answered
  # a state read, everything pushed before has been handled.
  defp settle(ext_channel), do: :sys.get_state(ext_channel.channel_pid)

  test "asks for the whole set on attach, then keeps it current from events", %{tmp_dir: tmp_dir} do
    {socket, device} = connect_device(tmp_dir, %{alarms: true})
    {:ok, attach_list, ext_channel} = join_extensions(socket, %{"alarms" => "0.1.0"})

    assert "alarms" in attach_list

    push(ext_channel, "alarms:attached", %{})
    assert_push("alarms:sync", %{})

    push(ext_channel, "alarms:snapshot", %{
      "alarms" => [%{"alarm" => "Elixir.MyApp.HighTemp", "description" => "too hot"}]
    })

    push(ext_channel, "alarms:raised", %{"alarm" => "MyApp.LowDisk", "description" => "nearly full"})
    push(ext_channel, "alarms:cleared", %{"alarm" => "MyApp.HighTemp"})
    settle(ext_channel)

    assert Alarms.current_alarms_for_device(device) == [{"MyApp.LowDisk", "nearly full"}]

    close_cleanly(ext_channel)
  end

  test "is not attached for a product that has it switched off", %{tmp_dir: tmp_dir} do
    {socket, device} = connect_device(tmp_dir, %{health: true})
    {:ok, attach_list, ext_channel} = join_extensions(socket, %{"alarms" => "0.1.0"})

    refute "alarms" in attach_list

    ref = push(ext_channel, "alarms:raised", %{"alarm" => "HighTemp"})
    assert_reply(ref, :error, "detach")

    assert Alarms.current_alarms_for_device(device) == nil

    close_cleanly(ext_channel)
  end
end

defmodule NervesHubWeb.DeviceMessageRecordingTest do
  @moduledoc """
  The device link records traffic where it actually crosses the wire, which
  means these are the tests that can tell whether it is recording at all.
  Everything above them can pass with the interception points removed.
  """

  # Not async: these tests write to the AnalyticsRepo, which is a ClickHouse
  # database that does not support concurrent writes.
  use NervesHubWeb.ChannelCase, async: false
  use Mimic
  use DefaultMocks

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.DeviceEvents
  alias NervesHub.Devices.DeviceMessage
  alias NervesHub.Devices.DeviceMessages
  alias NervesHub.Extensions
  alias NervesHub.Extensions.Health
  alias NervesHub.Fixtures
  alias NervesHubWeb.DeviceChannel
  alias NervesHubWeb.DeviceSocket

  setup do
    :ok = Buffer.flush(DeviceMessage)
    AnalyticsRepo.query("TRUNCATE TABLE device_messages", [])
    :ok
  end

  describe "the device channel" do
    test "records the join and the messages a device sends", %{tmp_dir: tmp_dir} do
      %{device: device, channel: channel} = join_device(tmp_dir)

      _ = push(channel, "fwup_progress", %{"value" => 42})
      _ = :sys.get_state(channel.channel_pid)

      messages = recorded(device)

      assert %{direction: "received", topic: "device", event: "join"} = find(messages, "join")

      assert %{direction: "received", topic: "device", payload: ~s({"value":42})} =
               find(messages, "fwup_progress")

      close_cleanly(channel)
    end

    test "records a fastlaned message the channel process never sees", %{tmp_dir: tmp_dir} do
      %{device: device, channel: channel} = join_device(tmp_dir)

      user = Fixtures.user_fixture()
      {:ok, _device} = DeviceEvents.reboot(device, user)

      _ = :sys.get_state(channel.channel_pid)

      assert %{direction: "sent", topic: "device", event: "reboot"} = find(recorded(device), "reboot")

      close_cleanly(channel)
    end

    test "does not record messages the channel intercepts and the device never sees", %{tmp_dir: tmp_dir} do
      %{device: device, channel: channel} = join_device(tmp_dir)

      :ok = DeviceEvents.updated(device)
      _ = :sys.get_state(channel.channel_pid)

      messages = recorded(device)

      # The join proves the recorder is alive, so the absence below is the
      # interception rule doing its job rather than nothing being recorded.
      assert find(messages, "join")
      refute find(messages, "updated")

      close_cleanly(channel)
    end
  end

  describe "web -> device extension events" do
    # These are recorded by whoever produces them rather than by
    # `Extensions.PubSub`, which stays free of the database so the connection
    # layer can be duplicated onto a node that has none. Which means a caller
    # can forget, and only a test would say so.
    test "records a health check requested from the web", %{tmp_dir: tmp_dir} do
      %{device: device, channel: channel} = join_device(tmp_dir)

      :ok = Health.request_health_check(device)

      assert %{direction: "sent", topic: "extensions", event: "health:check"} =
               find(recorded(device), "health:check")

      close_cleanly(channel)
    end

    test "records an extension being attached and detached", %{tmp_dir: tmp_dir} do
      %{device: device, channel: channel} = join_device(tmp_dir)

      :ok = Extensions.broadcast_extension_event(device, "attach", "health")
      :ok = Extensions.broadcast_extension_event(device, "detach", "health")

      messages = recorded(device)

      assert %{direction: "sent", topic: "extensions", payload: payload} = find(messages, "attach")
      assert payload =~ "health"
      assert %{direction: "sent", topic: "extensions"} = find(messages, "detach")

      close_cleanly(channel)
    end
  end

  defp join_device(tmp_dir) do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{version: "0.0.1", dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware, %{identifier: "recording-123"})

    %{db_cert: certificate} = Fixtures.device_certificate_fixture(device)

    params =
      for {k, v} <- Map.from_struct(device.firmware_metadata), into: %{} do
        {"nerves_fw_#{k}", v}
      end

    {:ok, socket} = connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})
    {:ok, %{}, channel} = subscribe_and_join(socket, DeviceChannel, "device:#{device.id}", params)

    %{device: device, channel: channel}
  end

  defp recorded(device) do
    :ok = Buffer.flush(DeviceMessage)
    DeviceMessages.recent(device)
  end

  defp find(messages, event), do: Enum.find(messages, &(&1.event == event))
end

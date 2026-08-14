defmodule NervesHubWeb.Extensions.HealthGeoTest do
  use NervesHubWeb.ChannelCase
  use DefaultMocks

  alias NervesHub.Devices.PubSub
  alias NervesHub.Extensions.Geo
  alias NervesHub.Extensions.Health
  alias NervesHub.Extensions.PubSub, as: ExtPubSub
  alias NervesHub.Fixtures
  alias NervesHubWeb.DeviceChannel
  alias NervesHubWeb.DeviceSocket
  alias NervesHubWeb.ExtensionsChannel
  # ---- Helpers ----
  alias Phoenix.Socket.Broadcast

  defp build_socket(tmp_dir) do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

    firmware =
      Fixtures.firmware_fixture(org_key, product, %{
        version: "0.0.1",
        dir: tmp_dir
      })

    _deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})

    device = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"]})
    %{db_cert: certificate} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    params = %{"device_api_version" => "2.2.0"}

    {:ok, _, _device_channel} =
      subscribe_and_join(socket, DeviceChannel, "device:#{device.id}", params)

    assert_push("extensions:get", _)

    {socket, device}
  end

  defp join_extensions(socket, extension_versions) do
    params = Map.merge(%{"device_api_version" => "2.2.0"}, extension_versions)
    {:ok, _attach_list, ext_channel} = subscribe_and_join(socket, ExtensionsChannel, "extensions", params)
    ext_channel
  end

  defp attach_extension(ext_channel, name) do
    push(ext_channel, "#{name}:attached", %{})
    :sys.get_state(ext_channel.channel_pid)
  end

  # ---- Extensions.Health ----

  describe "Extensions.Health attach" do
    test "assigns health_interval and health_timer on attach", %{tmp_dir: tmp_dir} do
      {socket, _device} = build_socket(tmp_dir)
      ext_channel = join_extensions(socket, %{"health" => "0.0.1"})

      push(ext_channel, "health:attached", %{})
      state = :sys.get_state(ext_channel.channel_pid)

      assert is_integer(state.assigns.health_interval)
      assert state.assigns.health_interval > 0
      assert state.assigns.health_timer != nil

      close_cleanly(ext_channel)
    end
  end

  describe "Extensions.Health detach" do
    test "cancels health timer and nils assigns on detach", %{tmp_dir: tmp_dir} do
      {socket, _device} = build_socket(tmp_dir)
      ext_channel = join_extensions(socket, %{"health" => "0.0.1"})
      attach_extension(ext_channel, "health")

      push(ext_channel, "health:detached", %{})
      state = :sys.get_state(ext_channel.channel_pid)

      assert is_nil(state.assigns.health_timer)

      close_cleanly(ext_channel)
    end
  end

  describe "Extensions.Health handle_info :check" do
    test "pushes health:check to device on :check message", %{tmp_dir: tmp_dir} do
      {socket, _device} = build_socket(tmp_dir)
      ext_channel = join_extensions(socket, %{"health" => "0.0.1"})
      attach_extension(ext_channel, "health")

      # attach/1 already sends {:Health, :check} to trigger an immediate check — consume it
      assert_push("health:check", %{})

      # Manually send another :check
      send(ext_channel.channel_pid, {Health, :check})

      assert_push("health:check", %{})

      close_cleanly(ext_channel)
    end
  end

  describe "Extensions.Health handle_in report — success" do
    test "saves health report and broadcasts health_check_report", %{tmp_dir: tmp_dir} do
      {socket, device} = build_socket(tmp_dir)
      ext_channel = join_extensions(socket, %{"health" => "0.0.1"})
      attach_extension(ext_channel, "health")

      # Consume the initial health:check push from attach
      assert_push("health:check", %{})

      # Subscribe to health report broadcasts via the Extension PubSub
      ExtPubSub.subscribe_reports(device.id)

      report = %{"value" => %{"metrics" => %{}}}
      push(ext_channel, "health:report", report)
      :sys.get_state(ext_channel.channel_pid)

      assert_receive %Broadcast{event: "health_check_report"}, 500

      close_cleanly(ext_channel)
    end

    test "handles empty metrics without crashing", %{tmp_dir: tmp_dir} do
      {socket, _device} = build_socket(tmp_dir)
      ext_channel = join_extensions(socket, %{"health" => "0.0.1"})
      attach_extension(ext_channel, "health")

      assert_push("health:check", %{})

      push(ext_channel, "health:report", %{"value" => %{}})
      :sys.get_state(ext_channel.channel_pid)

      assert Process.alive?(ext_channel.channel_pid)

      close_cleanly(ext_channel)
    end
  end

  # ---- Extensions.Geo ----

  describe "Extensions.Geo attach" do
    test "sends location_request on attach when geo_interval is 0", %{tmp_dir: tmp_dir} do
      # With geo_interval = 0, no timer is set but location_request is sent immediately
      Application.put_env(:nerves_hub, :extension_config, geo: [interval_minutes: 0])

      on_exit(fn -> Application.delete_env(:nerves_hub, :extension_config) end)

      {socket, _device} = build_socket(tmp_dir)
      ext_channel = join_extensions(socket, %{"geo" => "0.0.1"})

      push(ext_channel, "geo:attached", %{})
      state = :sys.get_state(ext_channel.channel_pid)

      # With interval 0, no timer assigned
      refute Map.has_key?(state.assigns, :geo_timer)

      assert_push("geo:location:request", %{})

      close_cleanly(ext_channel)
    end

    test "sets geo_timer when interval > 0", %{tmp_dir: tmp_dir} do
      Application.put_env(:nerves_hub, :extension_config, geo: [interval_minutes: 60])
      on_exit(fn -> Application.delete_env(:nerves_hub, :extension_config) end)

      {socket, _device} = build_socket(tmp_dir)
      ext_channel = join_extensions(socket, %{"geo" => "0.0.1"})

      push(ext_channel, "geo:attached", %{})
      state = :sys.get_state(ext_channel.channel_pid)

      assert state.assigns.geo_timer != nil
      assert state.assigns.geo_interval == 60

      assert_push("geo:location:request", %{})

      close_cleanly(ext_channel)
    end
  end

  describe "Extensions.Geo detach" do
    test "cancels geo timer and nils assigns on detach", %{tmp_dir: tmp_dir} do
      Application.put_env(:nerves_hub, :extension_config, geo: [interval_minutes: 60])
      on_exit(fn -> Application.delete_env(:nerves_hub, :extension_config) end)

      {socket, _device} = build_socket(tmp_dir)
      ext_channel = join_extensions(socket, %{"geo" => "0.0.1"})
      attach_extension(ext_channel, "geo")

      assert_push("geo:location:request", %{})

      push(ext_channel, "geo:detached", %{})
      state = :sys.get_state(ext_channel.channel_pid)

      assert is_nil(state.assigns.geo_timer)

      close_cleanly(ext_channel)
    end
  end

  describe "Extensions.Geo handle_in location:update" do
    test "updates connection metadata and broadcasts location:updated", %{tmp_dir: tmp_dir} do
      Application.put_env(:nerves_hub, :extension_config, geo: [interval_minutes: 0])
      on_exit(fn -> Application.delete_env(:nerves_hub, :extension_config) end)

      {socket, device} = build_socket(tmp_dir)
      ext_channel = join_extensions(socket, %{"geo" => "0.0.1"})
      attach_extension(ext_channel, "geo")

      assert_push("geo:location:request", %{})

      PubSub.subscribe(device.id)

      location = %{"lat" => 37.77, "lng" => -122.41}
      push(ext_channel, "geo:location:update", location)
      :sys.get_state(ext_channel.channel_pid)

      assert_receive %Broadcast{event: "location:updated"}, 500

      close_cleanly(ext_channel)
    end
  end

  describe "Extensions.Geo handle_info :location_request" do
    test "pushes geo:location:request on :location_request message", %{tmp_dir: tmp_dir} do
      Application.put_env(:nerves_hub, :extension_config, geo: [interval_minutes: 0])
      on_exit(fn -> Application.delete_env(:nerves_hub, :extension_config) end)

      {socket, _device} = build_socket(tmp_dir)
      ext_channel = join_extensions(socket, %{"geo" => "0.0.1"})
      attach_extension(ext_channel, "geo")

      # Consume the one from attach
      assert_push("geo:location:request", %{})

      send(ext_channel.channel_pid, {Geo, :location_request})

      assert_push("geo:location:request", %{})

      close_cleanly(ext_channel)
    end
  end
end

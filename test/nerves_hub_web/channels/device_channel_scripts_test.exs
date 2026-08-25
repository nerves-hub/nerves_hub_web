defmodule NervesHubWeb.DeviceChannelScriptsTest do
  use NervesHubWeb.ChannelCase
  use Mimic

  alias NervesHub.DeviceLink
  alias NervesHub.Fixtures
  alias NervesHubWeb.DeviceChannel
  alias NervesHubWeb.DeviceSocket

  # For fwup_progress tests we verify the stage/percent mapping by setting up
  # stubs BEFORE subscribing_and_joining so the channel process picks them up.

  alias Phoenix.Socket.Broadcast

  describe "scripts/run — connecting_code ref" do
    setup %{tmp_dir: tmp_dir} do
      {_user, _org, _product, _firmware, certificate, device} = build_device_fixtures(tmp_dir)

      stub(DeviceLink, :join, fn device_info, _params -> {:ok, device_info} end)
      stub(DeviceLink, :after_join, fn _device_info, _params -> :ok end)
      stub(DeviceLink, :fetch_connecting_code, fn _device_info -> nil end)

      params =
        for {k, v} <- Map.from_struct(device.firmware_metadata),
            into: %{"device_api_version" => "2.1.0"} do
          {"nerves_fw_#{k}", v}
        end

      {:ok, socket} =
        connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

      {:ok, %{}, device_channel} =
        subscribe_and_join(socket, DeviceChannel, "device:#{device.id}", params)

      allow(DeviceLink, self(), device_channel.channel_pid)
      _state = :sys.get_state(device_channel.channel_pid)

      {:ok, device_channel: device_channel}
    end

    test "fires connecting_code_success telemetry on success result", %{device_channel: device_channel} do
      test_pid = self()
      handler_id = {__MODULE__, :success, make_ref()}

      :telemetry.attach(
        handler_id,
        [:nerves_hub, :devices, :connecting_code_success],
        fn _event, measurements, _metadata, _config -> send(test_pid, {:telemetry_success, measurements}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      push(device_channel, "scripts/run", %{
        "ref" => "connecting_code",
        "result" => "ok",
        "return" => "0",
        "output" => "hello"
      })

      assert_receive {:telemetry_success, _}

      close_cleanly(device_channel)
    end

    test "fires connecting_code_failure telemetry when result is error", %{device_channel: device_channel} do
      test_pid = self()
      handler_id = {__MODULE__, :failure_error, make_ref()}

      :telemetry.attach(
        handler_id,
        [:nerves_hub, :devices, :connecting_code_failure],
        fn _event, _measurements, _metadata, _config -> send(test_pid, :telemetry_failure) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      push(device_channel, "scripts/run", %{
        "ref" => "connecting_code",
        "result" => "error",
        "return" => "1",
        "output" => "something failed"
      })

      assert_receive :telemetry_failure

      close_cleanly(device_channel)
    end

    test "fires connecting_code_failure telemetry when return is 'nil'", %{device_channel: device_channel} do
      test_pid = self()
      handler_id = {__MODULE__, :failure_nil, make_ref()}

      :telemetry.attach(
        handler_id,
        [:nerves_hub, :devices, :connecting_code_failure],
        fn _event, _measurements, _metadata, _config -> send(test_pid, :telemetry_failure) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      push(device_channel, "scripts/run", %{
        "ref" => "connecting_code",
        "result" => "ok",
        "return" => "nil",
        "output" => "unexpected"
      })

      assert_receive :telemetry_failure

      close_cleanly(device_channel)
    end
  end

  describe "scripts/run — arbitrary ref" do
    test "sends assembled output to waiting pid when ref matches", %{tmp_dir: tmp_dir} do
      {device_channel, _device} = join_device_channel(tmp_dir, "2.1.0")

      waiting_pid = self()

      send(device_channel.channel_pid, {:run_script, waiting_pid, "echo hello"})
      socket_state = :sys.get_state(device_channel.channel_pid)
      [ref] = Map.keys(socket_state.assigns.session.script_refs)

      push(device_channel, "scripts/run", %{
        "ref" => ref,
        "output" => "hello",
        "return" => "0",
        "result" => "ok"
      })

      _state = :sys.get_state(device_channel.channel_pid)

      assert_received {:output, output}
      assert String.contains?(output, "hello")

      close_cleanly(device_channel)
    end

    test "does nothing when ref is not in script_refs", %{tmp_dir: tmp_dir} do
      {device_channel, _device} = join_device_channel(tmp_dir)

      push(device_channel, "scripts/run", %{
        "ref" => "nonexistent-ref",
        "output" => "ignored",
        "return" => "0",
        "result" => "ok"
      })

      _state = :sys.get_state(device_channel.channel_pid)

      refute_received {:output, _}

      close_cleanly(device_channel)
    end
  end

  describe "handle_info :run_script" do
    test "stores ref in script_refs and pushes scripts/run when api version >= 2.1.0", %{tmp_dir: tmp_dir} do
      {device_channel, _device} = join_device_channel(tmp_dir, "2.1.0")

      waiting_pid = self()
      send(device_channel.channel_pid, {:run_script, waiting_pid, "echo test"})
      socket_state = :sys.get_state(device_channel.channel_pid)

      assert map_size(socket_state.assigns.session.script_refs) == 1
      [ref] = Map.keys(socket_state.assigns.session.script_refs)
      assert socket_state.assigns.session.script_refs[ref] == waiting_pid
      assert_push("scripts/run", %{"text" => "echo test", "ref" => ^ref})

      close_cleanly(device_channel)
    end

    test "sends {:error, :incompatible_version} to pid when api version < 2.1.0", %{tmp_dir: tmp_dir} do
      {device_channel, _device} = join_device_channel(tmp_dir, "2.0.0")

      waiting_pid = self()
      send(device_channel.channel_pid, {:run_script, waiting_pid, "echo test"})
      _state = :sys.get_state(device_channel.channel_pid)

      assert_received {:error, :incompatible_version}

      close_cleanly(device_channel)
    end
  end

  describe "handle_info :clear_script_ref" do
    test "removes the ref from script_refs", %{tmp_dir: tmp_dir} do
      {device_channel, _device} = join_device_channel(tmp_dir, "2.1.0")

      waiting_pid = self()
      send(device_channel.channel_pid, {:run_script, waiting_pid, "echo test"})
      socket_state = :sys.get_state(device_channel.channel_pid)
      [ref] = Map.keys(socket_state.assigns.session.script_refs)

      send(device_channel.channel_pid, {:clear_script_ref, ref})
      socket_state = :sys.get_state(device_channel.channel_pid)

      assert socket_state.assigns.session.script_refs == %{}

      close_cleanly(device_channel)
    end
  end

  describe "handle_out deployment_updated" do
    test "updates deployment_id on device_info from payload", %{tmp_dir: tmp_dir} do
      {user, _org, _product, firmware, certificate, device} = build_device_fixtures(tmp_dir)

      stub(DeviceLink, :join, fn device_info, _params -> {:ok, device_info} end)
      stub(DeviceLink, :after_join, fn _device_info, _params -> :ok end)
      stub(DeviceLink, :fetch_connecting_code, fn _device_info -> nil end)
      stub(DeviceLink, :maybe_send_archive, fn _device_info, _version, _opts -> :ok end)

      # Assign a deployment group so the channel subscribes to its topic
      deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})
      {:ok, device} = NervesHub.Devices.update_device(device, %{deployment_id: deployment_group.id})

      params =
        for {k, v} <- Map.from_struct(device.firmware_metadata),
            into: %{"device_api_version" => "2.1.0"} do
          {"nerves_fw_#{k}", v}
        end

      {:ok, socket} =
        connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

      {:ok, %{}, device_channel} =
        subscribe_and_join(socket, DeviceChannel, "device:#{device.id}", params)

      allow(DeviceLink, self(), device_channel.channel_pid)
      _state = :sys.get_state(device_channel.channel_pid)

      new_deployment_id = deployment_group.id

      Phoenix.PubSub.broadcast(
        NervesHub.PubSub,
        "deployment:#{deployment_group.id}",
        %Broadcast{
          topic: "deployment:#{deployment_group.id}",
          event: "deployment_updated",
          payload: %{deployment_id: new_deployment_id}
        }
      )

      socket_state = :sys.get_state(device_channel.channel_pid)
      assert socket_state.assigns.device_info.deployment_id == new_deployment_id

      close_cleanly(device_channel)
    end
  end

  describe "send_connecting_code" do
    test "pushes scripts/run with connecting_code ref when api version >= 2.1.0 and connecting code exists", %{
      tmp_dir: tmp_dir
    } do
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

      device =
        Fixtures.device_fixture(org, product, firmware, %{
          tags: ["beta"],
          connecting_code: "echo hello"
        })

      %{db_cert: certificate} = Fixtures.device_certificate_fixture(device)

      params =
        for {k, v} <- Map.from_struct(device.firmware_metadata),
            into: %{"device_api_version" => "2.1.0"} do
          {"nerves_fw_#{k}", v}
        end

      {:ok, socket} =
        connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

      {:ok, %{}, device_channel} =
        subscribe_and_join(socket, DeviceChannel, "device:#{device.id}", params)

      _state = :sys.get_state(device_channel.channel_pid)

      assert_push("scripts/run", %{"ref" => "connecting_code"})

      close_cleanly(device_channel)
    end
  end

  # ---- helpers ----

  defp build_device_fixtures(tmp_dir) do
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

    {user, org, product, firmware, certificate, device}
  end

  defp join_device_channel(tmp_dir, device_api_version \\ "2.1.0") do
    {_user, _org, _product, _firmware, certificate, device} = build_device_fixtures(tmp_dir)

    params =
      for {k, v} <- Map.from_struct(device.firmware_metadata),
          into: %{"device_api_version" => device_api_version} do
        {"nerves_fw_#{k}", v}
      end

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, %{}, device_channel} =
      subscribe_and_join(socket, DeviceChannel, "device:#{device.id}", params)

    _state = :sys.get_state(device_channel.channel_pid)

    {device_channel, device}
  end
end

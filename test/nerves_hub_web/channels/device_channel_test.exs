defmodule NervesHubWeb.DeviceChannelTest do
  use NervesHubWeb.ChannelCase
  use DefaultMocks

  import TrackerHelper

  alias NervesHub.AuditLogs
  alias NervesHub.Devices
  alias NervesHub.Fixtures
  alias NervesHub.Repo
  alias NervesHubWeb.DeviceChannel
  alias NervesHubWeb.DeviceSocket
  alias NervesHubWeb.ExtensionsChannel

  test "extensions are requested from device if version is above 2.2.0" do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, device_channel} =
      subscribe_and_join(socket, DeviceChannel, "device", %{"device_api_version" => "2.2.0"})

    assert_push("extensions:get", _)

    {:ok, _, _extensions_channel} =
      subscribe_and_join(socket, ExtensionsChannel, "extensions", %{
        "geo" => "1.0.0",
        "health" => "1.0.0"
      })

    assert_online_and_available(device)
    close_cleanly(device_channel)
  end

  test "presence connection information" do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    subscribe_for_updates(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, device_channel} = subscribe_and_join(socket, DeviceChannel, "device")

    assert_online_and_available(device)
    close_cleanly(device_channel)
  end

  test "fwup_public_keys requested on connect" do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    params =
      for {k, v} <- Map.from_struct(device.firmware_metadata), into: %{} do
        case k do
          :uuid -> {"nerves_fw_uuid", Ecto.UUID.generate()}
          _ -> {"nerves_fw_#{k}", v}
        end
      end

    params = Map.put(params, "fwup_public_keys", "on_connect")

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, %{}, device_channel} = subscribe_and_join(socket, DeviceChannel, "device", params)

    assert_push("fwup_public_keys", %{keys: [_]})

    assert_online_and_available(device)
    close_cleanly(device_channel)
  end

  test "archive_public_keys requested on connect" do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    params =
      for {k, v} <- Map.from_struct(device.firmware_metadata), into: %{} do
        case k do
          :uuid -> {"nerves_fw_uuid", Ecto.UUID.generate()}
          _ -> {"nerves_fw_#{k}", v}
        end
      end

    params = Map.put(params, "archive_public_keys", "on_connect")

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, %{}, device_channel} = subscribe_and_join(socket, DeviceChannel, "device", params)

    assert_push("archive_public_keys", %{keys: [_]})

    assert_online_and_available(device)
    close_cleanly(device_channel)
  end

  test "if archive is sent on connect an audit log is not created" do
    %{device: device, certificate: certificate, params: params, archive_uuid: archive_uuid} =
      archive_setup()

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    audit_log_count_before =
      Repo.aggregate(AuditLogs.with_description("Archive update triggered%"), :count)

    {:ok, %{}, device_channel} = subscribe_and_join(socket, DeviceChannel, "device", params)

    assert_push("archive", %{uuid: ^archive_uuid})

    assert audit_log_count_before ==
             Repo.aggregate(AuditLogs.with_description("Archive update triggered%"), :count)

    assert_online_and_available(device)
    close_cleanly(device_channel)
  end

  test "if archive is sent when an archive updates an audit log is created" do
    %{device: device, certificate: certificate, params: params} = archive_setup()

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, %{}, device_channel} = subscribe_and_join(socket, DeviceChannel, "device", params)

    Phoenix.PubSub.broadcast(
      NervesHub.PubSub,
      "device:#{device.id}",
      %Phoenix.Socket.Broadcast{event: "archives/updated"}
    )

    _ = :sys.get_state(device_channel.channel_pid)

    assert Repo.exists?(AuditLogs.with_description("Archive update triggered for%"))

    assert_online_and_available(device)
    close_cleanly(device_channel)
  end

  test "if archive is sent when a device updates an audit log is created" do
    %{device: device, certificate: certificate, params: params} = archive_setup()

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, %{}, device_channel} = subscribe_and_join(socket, DeviceChannel, "device", params)

    Phoenix.PubSub.broadcast(
      NervesHub.PubSub,
      "device:#{device.id}",
      %Phoenix.Socket.Broadcast{event: "devices/updated"}
    )

    _ = :sys.get_state(device_channel.channel_pid)

    assert Repo.exists?(AuditLogs.with_description("Archive update triggered for%"))

    assert_online_and_available(device)
    close_cleanly(device_channel)
  end

  test "the first fwup_progress marks an update as happening" do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _join_reply, device_channel} =
      subscribe_and_join(socket, DeviceChannel, "device")

    assert_online_and_available(device)

    push(device_channel, "fwup_progress", %{"value" => 10})

    # Since fwup_progress doesn't reply, we need to use sys to grab the socket
    # _after_ the handle_in has run
    state = :sys.get_state(device_channel.channel_pid)
    assert state.assigns.update_started?

    close_cleanly(device_channel)
  end

  test "set connection types for the device" do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _join_reply, device_channel} =
      subscribe_and_join(socket, DeviceChannel, "device")

    push(device_channel, "connection_types", %{"values" => ["ethernet", "wifi"]})

    # we need to let the channel process all messages before we can
    # check the state of the device's connection types
    _socket = :sys.get_state(device_channel.channel_pid)

    device = NervesHub.Repo.reload(device) |> NervesHub.Repo.preload(:latest_connection)
    assert device.latest_connection.metadata["connection_types"] == ["ethernet", "wifi"]

    close_cleanly(device_channel)
  end

  test "deployment information is updated when the deployment is cleared" do
    user = Fixtures.user_fixture()
    {device, _firmware, deployment_group} = device_fixture(user, %{identifier: "123"})
    Devices.update_deployment_group(device, deployment_group)

    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _join_reply, device_channel} =
      subscribe_and_join(socket, DeviceChannel, "device")

    assert_online_and_available(device)

    refute is_nil(device_channel.assigns.device.deployment_id)
    refute is_nil(device_channel.assigns.deployment_channel)

    Devices.clear_deployment_group(device)

    # we need to let the channel process all messages before we can
    # check the state of the device's connection types
    state = :sys.get_state(device_channel.channel_pid)

    assert is_nil(state.assigns.device.deployment_id)
    assert is_nil(state.assigns.deployment_channel)

    close_cleanly(device_channel)
  end

  test "deployment information is updated when the device joins a new deployment" do
    user = Fixtures.user_fixture()
    {device, firmware, deployment_group} = device_fixture(user, %{identifier: "123"})
    Devices.update_deployment_group(device, deployment_group)

    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _join_reply, device_channel} =
      subscribe_and_join(socket, DeviceChannel, "device")

    assert device_channel.assigns.device.deployment_id == deployment_group.id
    refute is_nil(device_channel.assigns.deployment_channel)

    device = NervesHub.Repo.preload(device, :org)

    new_deployment_group =
      Fixtures.deployment_group_fixture(device.org, firmware, %{name: "Super Deployment"})

    Devices.update_deployment_group(device, new_deployment_group)

    # we need to let the channel process all messages before we can
    # check the state of the device's connection types
    state = :sys.get_state(device_channel.channel_pid)

    assert state.assigns.device.deployment_id == new_deployment_group.id
    refute is_nil(state.assigns.deployment_channel)

    close_cleanly(device_channel)
  end

  describe "unhandled messages are caught" do
    test "handle_info" do
      user = Fixtures.user_fixture()
      {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"})
      %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

      subscribe_for_updates(device)

      {:ok, socket} =
        connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

      {:ok, _join_reply, device_channel} =
        subscribe_and_join(socket, DeviceChannel, "device")

      assert_online_and_available(device)

      send(device_channel.channel_pid, {"do_you_like_dem_apples", %{"apples" => 5}})

      close_cleanly(device_channel)
    end

    test "handle_in" do
      user = Fixtures.user_fixture()
      {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"})
      %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

      {:ok, socket} =
        connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

      {:ok, _join_reply, device_channel} =
        subscribe_and_join(socket, DeviceChannel, "device")

      ref = push(device_channel, "do_you_like_dem_apples", %{"apples" => 5})
      refute_reply(ref, %{})

      close_cleanly(device_channel)
    end
  end

  def device_fixture(user, device_params \\ %{}, org \\ nil) do
    org = org || Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)

    firmware =
      Fixtures.firmware_fixture(org_key, product, %{
        version: "0.0.1"
      })

    deployment_group = Fixtures.deployment_group_fixture(org, firmware)

    params = Enum.into(device_params, %{tags: ["beta", "beta-edge"]})

    device =
      Fixtures.device_fixture(
        org,
        product,
        firmware,
        params
      )

    {device, firmware, deployment_group}
  end

  defp archive_setup() do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user, %{name: "BigOrg2022"})
    product = Fixtures.product_fixture(user, org, %{name: "Hop"})
    org_key = Fixtures.org_key_fixture(org, user)
    archive = %{uuid: archive_uuid} = Fixtures.archive_fixture(org_key, product)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: System.tmp_dir()})
    deployment_group = Fixtures.deployment_group_fixture(org, firmware, %{archive_id: archive.id})

    {device, _firmware, _deployment_group} =
      device_fixture(user, %{identifier: "123", deployment_id: deployment_group.id})

    %{db_cert: certificate} = Fixtures.device_certificate_fixture(device)

    params =
      for {k, v} <- Map.from_struct(device.firmware_metadata),
          into: %{"device_api_version" => "2.0.1"} do
        case k do
          :uuid -> {"nerves_fw_uuid", Ecto.UUID.generate()}
          _ -> {"nerves_fw_#{k}", v}
        end
      end

    %{device: device, certificate: certificate, params: params, archive_uuid: archive_uuid}
  end
end

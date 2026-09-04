defmodule NervesHubWeb.DeviceChannelTest do
  use NervesHubWeb.ChannelCase
  use Mimic
  use DefaultMocks

  import TrackerHelper

  alias NervesHub.Accounts
  alias NervesHub.Accounts.OrgKey
  alias NervesHub.AuditLogs
  alias NervesHub.DeviceEvents
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.Deployments
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceFirmware
  alias NervesHub.Devices.Updates
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.Products.Notification
  alias NervesHub.Repo
  alias NervesHub.Support.EspIdf
  alias NervesHubWeb.DeviceChannel
  alias NervesHubWeb.DeviceSocket
  alias NervesHubWeb.ExtensionsChannel
  alias Phoenix.Socket.Broadcast

  describe "firmware_validation_status" do
    test "if the param is missing, then status is marked as :unknown", %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, tmp_dir)
      %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

      params =
        for {k, v} <- Map.from_struct(device.firmware_metadata), into: %{} do
          {"nerves_fw_#{k}", v}
        end

      {:ok, socket} =
        connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

      {:ok, %{}, device_channel} = subscribe_and_join(socket, DeviceChannel, "device:#{device.id}", params)

      # we need to let the channel process all messages before we can
      # check if the devices firmware_validation_status has been updated
      _socket = :sys.get_state(device_channel.channel_pid)

      device = Repo.reload(device)
      assert device.firmware_validation_status == :unknown

      [df] = Repo.all(DeviceFirmware)

      refute is_nil(device.current_device_firmware_id)

      assert df.id == device.current_device_firmware_id
      assert df.firmware_validation_status == :unknown

      # assert_online_and_available(device)
      close_cleanly(device_channel)
    end

    test "if meta.firmware_validated is false, then mark as :not_validated", %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, tmp_dir)
      %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

      params =
        for {k, v} <- Map.from_struct(device.firmware_metadata), into: %{} do
          {"nerves_fw_#{k}", v}
        end
        |> Map.put("meta", %{firmware_validated: false})

      {:ok, socket} =
        connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

      {:ok, %{}, device_channel} = subscribe_and_join(socket, DeviceChannel, "device:#{device.id}", params)

      # we need to let the channel process all messages before we can
      # check if the devices firmware_validation_status has been updated
      _socket = :sys.get_state(device_channel.channel_pid)

      device = Repo.reload(device)
      assert device.firmware_validation_status == :not_validated

      [df] = Repo.all(DeviceFirmware)

      refute is_nil(device.current_device_firmware_id)

      assert df.id == device.current_device_firmware_id
      assert df.firmware_validation_status == :not_validated

      # assert_online_and_available(device)
      close_cleanly(device_channel)
    end

    test "if meta.firmware_validated is true, then mark as :validated", %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, tmp_dir)
      %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

      params =
        for {k, v} <- Map.from_struct(device.firmware_metadata), into: %{} do
          {"nerves_fw_#{k}", v}
        end
        |> Map.put("meta", %{firmware_validated: true})

      {:ok, socket} =
        connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

      {:ok, %{}, device_channel} = subscribe_and_join(socket, DeviceChannel, "device:#{device.id}", params)

      # we need to let the channel process all messages before we can
      # check if the devices firmware_validation_status has been updated
      _socket = :sys.get_state(device_channel.channel_pid)

      device = Repo.reload(device)
      assert device.firmware_validation_status == :validated

      [df] = Repo.all(DeviceFirmware)

      refute is_nil(device.current_device_firmware_id)

      assert df.id == device.current_device_firmware_id
      assert df.firmware_validation_status == :validated

      # assert_online_and_available(device)
      close_cleanly(device_channel)
    end

    test "a device can send an update when its firmware is validated", %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, tmp_dir)
      %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

      params =
        for {k, v} <- Map.from_struct(device.firmware_metadata), into: %{} do
          {"nerves_fw_#{k}", v}
        end
        |> Map.put("meta", %{firmware_validated: false})

      {:ok, socket} =
        connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

      {:ok, %{}, device_channel} = subscribe_and_join(socket, DeviceChannel, "device:#{device.id}", params)

      # we need to let the channel process all messages before we can
      # check if the devices firmware_validation_status has been updated
      _socket = :sys.get_state(device_channel.channel_pid)

      device = Repo.reload(device)
      assert device.firmware_validation_status == :not_validated

      [df] = Repo.all(DeviceFirmware)

      refute is_nil(device.current_device_firmware_id)

      assert df.id == device.current_device_firmware_id
      assert df.firmware_validation_status == :not_validated

      push(device_channel, "firmware_validated", %{})

      _socket = :sys.get_state(device_channel.channel_pid)

      device = Repo.reload(device)
      assert device.firmware_validation_status == :validated

      df = Repo.reload(df)
      assert df.firmware_validation_status == :validated

      assert Repo.exists?(AuditLogs.with_description("Device #{device.identifier} has validated its firmware"))

      # assert_online_and_available(device)
      close_cleanly(device_channel)
    end
  end

  describe "firmware_auto_revert_detected" do
    test "if the meta key is missing from params then firmware_auto_revert_detected is set to false", %{
      tmp_dir: tmp_dir
    } do
      user = Fixtures.user_fixture()
      {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, tmp_dir)
      %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

      params =
        for {k, v} <- Map.from_struct(device.firmware_metadata), into: %{} do
          {"nerves_fw_#{k}", v}
        end
        |> Map.put("device_api_version", "2.2.0")

      {:ok, socket} =
        connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

      {:ok, %{}, device_channel} = subscribe_and_join(socket, DeviceChannel, "device:#{device.id}", params)

      # we need to let the channel process all messages before we can
      # check if the devices firmware_validation_status has been updated
      _socket = :sys.get_state(device_channel.channel_pid)

      device = Repo.reload(device)
      refute device.firmware_auto_revert_detected

      # assert_online_and_available(device)
      close_cleanly(device_channel)
    end

    test "if the meta key is present, but firmware_auto_revert_detected is missing, then firmware_auto_revert_detected is set to false",
         %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, tmp_dir)
      %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

      params =
        for {k, v} <- Map.from_struct(device.firmware_metadata), into: %{} do
          {"nerves_fw_#{k}", v}
        end
        |> Map.put("device_api_version", "2.2.0")
        |> Map.put("meta", %{})

      {:ok, socket} =
        connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

      {:ok, %{}, device_channel} = subscribe_and_join(socket, DeviceChannel, "device:#{device.id}", params)

      # we need to let the channel process all messages before we can
      # check if the devices firmware_validation_status has been updated
      _socket = :sys.get_state(device_channel.channel_pid)

      device = Repo.reload(device)
      refute device.firmware_auto_revert_detected

      # assert_online_and_available(device)
      close_cleanly(device_channel)
    end

    test "if the meta key is present, and firmware_auto_revert_detected is true, then firmware_auto_revert_detected is set to true",
         %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, tmp_dir)
      %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

      params =
        for {k, v} <- Map.from_struct(device.firmware_metadata), into: %{} do
          {"nerves_fw_#{k}", v}
        end
        |> Map.put("device_api_version", "2.2.0")
        |> Map.put("meta", %{"firmware_auto_revert_detected" => true})

      {:ok, socket} =
        connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

      {:ok, %{}, device_channel} = subscribe_and_join(socket, DeviceChannel, "device:#{device.id}", params)

      # we need to let the channel process all messages before we can
      # check if the devices firmware_validation_status has been updated
      _socket = :sys.get_state(device_channel.channel_pid)

      device = Repo.reload(device)
      assert device.firmware_auto_revert_detected

      # assert_online_and_available(device)
      close_cleanly(device_channel)
    end
  end

  test "the extensions request tells the device which versions it can have", %{tmp_dir: tmp_dir} do
    # This is the only point in the handshake where the platform speaks before
    # the device commits to a version, so what it carries is what lets a device
    # implementing two versions of an extension pick the one both sides have.
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, tmp_dir)
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, device_channel} =
      subscribe_and_join(socket, DeviceChannel, "device:#{device.id}", %{"device_api_version" => "2.2.0"})

    assert_push("extensions:get", %{"extensions" => advertised})

    assert advertised == NervesHub.Extensions.advertisement()
    assert advertised["health"] == ["0.0.1"]

    close_cleanly(device_channel)
  end

  test "extensions are requested from device if version is above 2.2.0", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, tmp_dir)
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, device_channel} =
      subscribe_and_join(socket, DeviceChannel, "device:#{device.id}", %{"device_api_version" => "2.2.0"})

    assert_push("extensions:get", _)

    {:ok, _, _extensions_channel} =
      subscribe_and_join(socket, ExtensionsChannel, "extensions", %{
        "geo" => "1.0.0",
        "health" => "1.0.0"
      })

    assert_online_and_available(device)
    close_cleanly(device_channel)
  end

  test "presence connection information", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, tmp_dir)
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    subscribe_for_updates(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, device_channel} = subscribe_and_join(socket, DeviceChannel, "device:#{device.id}")

    assert_online_and_available(device)
    close_cleanly(device_channel)
  end

  test "fwup_public_keys requested on connect", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, tmp_dir)
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    params =
      for {k, v} <- Map.from_struct(device.firmware_metadata), into: %{} do
        case k do
          :uuid -> {"nerves_fw_uuid", Ecto.UUID.generate()}
          _ -> {"nerves_fw_#{k}", v}
        end
      end

    params = Map.put(params, "fwup_public_keys", "on_connect")
    fwup_key = seed_other_scheme_keys(device, user)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, %{}, device_channel} = subscribe_and_join(socket, DeviceChannel, "device:#{device.id}", params)

    assert_push("fwup_public_keys", %{keys: [^fwup_key]})

    assert_online_and_available(device)
    close_cleanly(device_channel)
  end

  test "the firmware keys sent follow the device's update tool", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, tmp_dir)
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)
    _fwup_key = seed_other_scheme_keys(device, user)
    esp_idf_key = EspIdf.signing_public_key()

    # What nerves-hub-link-esp32 sends on join, plus the request for keys.
    params = %{
      "device_api_version" => "2.2.0",
      "update_tool" => "esp-idf",
      "esp_idf_project_name" => "my_app",
      "esp_idf_version" => "1.0.0",
      "esp_idf_app_elf_sha256" => Base.encode16(:crypto.strong_rand_bytes(32), case: :lower),
      "esp_idf_ver" => "v5.2.1",
      "esp_idf_chip_id" => 9,
      "fwup_public_keys" => "on_connect"
    }

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, %{}, device_channel} = subscribe_and_join(socket, DeviceChannel, "device:#{device.id}", params)

    assert_push("fwup_public_keys", %{keys: [^esp_idf_key]})

    assert_online_and_available(device)
    close_cleanly(device_channel)
  end

  test "archive_public_keys requested on connect", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, tmp_dir)
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    params =
      for {k, v} <- Map.from_struct(device.firmware_metadata), into: %{} do
        case k do
          :uuid -> {"nerves_fw_uuid", Ecto.UUID.generate()}
          _ -> {"nerves_fw_#{k}", v}
        end
      end

    params = Map.put(params, "archive_public_keys", "on_connect")
    fwup_key = seed_other_scheme_keys(device, user)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, %{}, device_channel} = subscribe_and_join(socket, DeviceChannel, "device:#{device.id}", params)

    assert_push("archive_public_keys", %{keys: [^fwup_key]})

    assert_online_and_available(device)
    close_cleanly(device_channel)
  end

  test "if archive is sent on connect an audit log is not created", %{tmp_dir: tmp_dir} do
    %{device: device, certificate: certificate, params: params, archive_uuid: archive_uuid} =
      archive_setup(tmp_dir)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    audit_log_count_before =
      Repo.aggregate(AuditLogs.with_description("Archive update triggered%"), :count)

    {:ok, %{}, device_channel} = subscribe_and_join(socket, DeviceChannel, "device:#{device.id}", params)

    assert_push("archive", %{uuid: ^archive_uuid})

    assert audit_log_count_before ==
             Repo.aggregate(AuditLogs.with_description("Archive update triggered%"), :count)

    assert_online_and_available(device)
    close_cleanly(device_channel)
  end

  test "if archive is sent when an archive updates an audit log is created", %{tmp_dir: tmp_dir} do
    %{device: device, certificate: certificate, params: params} = archive_setup(tmp_dir)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, %{}, device_channel} = subscribe_and_join(socket, DeviceChannel, "device:#{device.id}", params)

    Phoenix.PubSub.broadcast(
      NervesHub.PubSub,
      "device:#{device.id}",
      %Broadcast{event: "archives/updated"}
    )

    _ = :sys.get_state(device_channel.channel_pid)

    assert Repo.exists?(AuditLogs.with_description("Archive update triggered for%"))

    assert_online_and_available(device)
    close_cleanly(device_channel)
  end

  test "if archive is sent when a device updates an audit log is created", %{tmp_dir: tmp_dir} do
    %{device: device, certificate: certificate, params: params} = archive_setup(tmp_dir)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, %{}, device_channel} = subscribe_and_join(socket, DeviceChannel, "device:#{device.id}", params)

    DeviceEvents.updated(device)

    _ = :sys.get_state(device_channel.channel_pid)

    assert Repo.exists?(AuditLogs.with_description("Archive update triggered for%"))

    assert_online_and_available(device)
    close_cleanly(device_channel)
  end

  test "set connection types for the device", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, tmp_dir)
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _join_reply, device_channel} =
      subscribe_and_join(socket, DeviceChannel, "device:#{device.id}")

    push(device_channel, "connection_types", %{"values" => ["ethernet", "wifi"]})

    # we need to let the channel process all messages before we can
    # check the state of the device's connection types
    _socket = :sys.get_state(device_channel.channel_pid)

    device = NervesHub.Repo.reload(device) |> NervesHub.Repo.preload(:latest_connection)
    assert device.latest_connection.metadata["connection_types"] == ["ethernet", "wifi"]

    close_cleanly(device_channel)
  end

  test "deployment information is updated when the deployment is cleared", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    {device, _firmware, deployment_group} = device_fixture(user, %{identifier: "123"}, tmp_dir)
    Deployments.update_deployment_group(device, deployment_group)

    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _join_reply, device_channel} =
      subscribe_and_join(socket, DeviceChannel, "device:#{device.id}")

    assert_online_and_available(device)

    refute is_nil(device_channel.assigns.session.device_info.deployment_id)
    refute is_nil(device_channel.assigns.session.deployment_topic)

    Deployments.clear_deployment_group(device)

    # we need to let the channel process all messages before we can
    # check the state of the device's connection types
    state = :sys.get_state(device_channel.channel_pid)

    assert is_nil(state.assigns.session.device_info.deployment_id)
    assert is_nil(state.assigns.session.deployment_topic)

    close_cleanly(device_channel)
  end

  test "deployment information is updated when the device joins a new deployment", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    {device, firmware, deployment_group} = device_fixture(user, %{identifier: "123"}, tmp_dir)
    Deployments.update_deployment_group(device, deployment_group)

    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _join_reply, device_channel} =
      subscribe_and_join(socket, DeviceChannel, "device:#{device.id}")

    assert device_channel.assigns.session.device_info.deployment_id == deployment_group.id
    refute is_nil(device_channel.assigns.session.deployment_topic)

    device = NervesHub.Repo.preload(device, :org)

    new_deployment_group =
      Fixtures.deployment_group_fixture(firmware, %{name: "Super Deployment", user: user})

    Deployments.update_deployment_group(device, new_deployment_group)

    # we need to let the channel process all messages before we can
    # check the state of the device's connection types
    state = :sys.get_state(device_channel.channel_pid)

    assert state.assigns.session.device_info.deployment_id == new_deployment_group.id
    refute is_nil(state.assigns.session.deployment_topic)

    close_cleanly(device_channel)
  end

  test "matching deployment group is set on join when device has no deployment group", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    {device, _firmware, deployment_group} = device_fixture(user, %{identifier: "123"}, tmp_dir)
    refute device.deployment_id

    {:ok, deployment_group} =
      ManagedDeployments.update_deployment_group(deployment_group, %{is_active: true}, user)

    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _join_reply, device_channel} =
      subscribe_and_join(socket, DeviceChannel, "device:#{device.id}")

    assert device_channel.assigns.session.device_info.deployment_id == deployment_group.id

    close_cleanly(device_channel)
  end

  test "deployment group is removed on join when conditions no longer match", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    {device, _firmware, deployment_group} = device_fixture(user, %{identifier: "123"}, tmp_dir)
    Deployments.update_deployment_group(device, deployment_group)

    {:ok, _deployment_group} =
      ManagedDeployments.update_deployment_group(
        deployment_group,
        %{
          conditions: %{"version" => "< 0.0.1"}
        },
        user
      )

    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _join_reply, device_channel} =
      subscribe_and_join(socket, DeviceChannel, "device:#{device.id}")

    refute device_channel.assigns.session.device_info.deployment_id

    close_cleanly(device_channel)
  end

  test "deployment group is not removed when matching conditions are met", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    {device, _firmware, deployment_group} = device_fixture(user, %{identifier: "123"}, tmp_dir)
    device = Deployments.update_deployment_group(device, deployment_group)
    assert device.deployment_id == deployment_group.id

    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _join_reply, device_channel} =
      subscribe_and_join(socket, DeviceChannel, "device:#{device.id}")

    assert device_channel.assigns.session.device_info.deployment_id == deployment_group.id

    close_cleanly(device_channel)
  end

  describe "device network interface" do
    test "updates when incoming interface is different than the current one",
         %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, tmp_dir)
      %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

      subscribe_for_updates(device)

      {:ok, socket} =
        connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

      params =
        for {k, v} <- Map.from_struct(device.firmware_metadata), into: %{} do
          {"nerves_fw_#{k}", v}
        end
        |> Map.put("device_api_version", "2.2.0")

      {:ok, _join_reply, device_channel} =
        subscribe_and_join(socket, DeviceChannel, "device:#{device.id}", params)

      assert_online_and_available(device)

      push(device_channel, "report_network_interface", %{"interface" => "eth0"})
      _socket = :sys.get_state(device_channel.channel_pid)

      connection = Connections.get_latest_for_device(device.id)
      assert connection.network_interface == :ethernet

      close_cleanly(device_channel)
    end
  end

  describe "unhandled messages are caught" do
    test "handle_info", %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, tmp_dir)
      %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

      subscribe_for_updates(device)

      {:ok, socket} =
        connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

      {:ok, _join_reply, device_channel} =
        subscribe_and_join(socket, DeviceChannel, "device:#{device.id}")

      assert_online_and_available(device)

      send(device_channel.channel_pid, {"do_you_like_dem_apples", %{"apples" => 5}})

      close_cleanly(device_channel)
    end

    test "handle_in", %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "123"}, tmp_dir)
      %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

      {:ok, socket} =
        connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

      {:ok, _join_reply, device_channel} =
        subscribe_and_join(socket, DeviceChannel, "device:#{device.id}")

      ref = push(device_channel, "do_you_like_dem_apples", %{"apples" => 5})
      refute_reply(ref, %{})

      close_cleanly(device_channel)
    end
  end

  describe "update mode" do
    setup %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      {device, _firmware, _deployment_group} = device_fixture(user, %{identifier: "update-mode"}, tmp_dir)
      %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

      %{device: device, certificate: certificate, user: user}
    end

    test "the device is told its mode when it joins", %{device: device, certificate: certificate} do
      device_channel = join_device(device, certificate, "2.4.0")

      assert_push("update_mode", %{"mode" => "automatic", "managed_updates_allowed" => false})

      close_cleanly(device_channel)
    end

    test "a device too old to understand the message is not sent it", %{
      device: device,
      certificate: certificate
    } do
      device_channel = join_device(device, certificate, "2.3.0")

      refute_push("update_mode", _)

      close_cleanly(device_channel)
    end

    test "a device without the grant is refused, and told the mode it still has", %{
      device: device,
      certificate: certificate
    } do
      device_channel = join_device(device, certificate, "2.4.0")
      assert_push("update_mode", %{"mode" => "automatic"})

      push(device_channel, "set_update_mode", %{"mode" => "device_managed"})

      assert_push("update_mode", %{"mode" => "automatic", "error" => "not_permitted"})
      assert Repo.reload(device).update_mode == :automatic

      close_cleanly(device_channel)
    end

    test "a device with the grant may manage its own updates", %{
      device: device,
      certificate: certificate,
      user: user
    } do
      {:ok, device} = Updates.set_managed_updates_allowed(device, true, user)

      device_channel = join_device(device, certificate, "2.4.0")
      assert_push("update_mode", %{"mode" => "automatic", "managed_updates_allowed" => true})

      push(device_channel, "set_update_mode", %{"mode" => "device_managed"})

      assert_push("update_mode", %{"mode" => "device_managed"})
      assert Repo.reload(device).update_mode == :device_managed

      close_cleanly(device_channel)
    end

    test "a device can never freeze itself over the socket", %{
      device: device,
      certificate: certificate,
      user: user
    } do
      {:ok, device} = Updates.set_managed_updates_allowed(device, true, user)

      device_channel = join_device(device, certificate, "2.4.0")
      assert_push("update_mode", %{"mode" => "automatic"})

      push(device_channel, "set_update_mode", %{"mode" => "off"})

      assert_push("update_mode", %{"mode" => "automatic", "error" => "not_permitted"})
      assert Repo.reload(device).update_mode == :automatic

      close_cleanly(device_channel)
    end

    test "a device below the advertised version is still answered when it asks", %{
      device: device,
      certificate: certificate
    } do
      device_channel = join_device(device, certificate, "2.3.0")

      # Nothing unsolicited for a device that would not understand it...
      refute_push("update_mode", _)

      push(device_channel, "set_update_mode", %{"mode" => "device_managed"})

      # ...but a device that asks has shown it understands the answer, and acting
      # on a request without answering it is how the two end up disagreeing.
      assert_push("update_mode", %{"mode" => "automatic", "error" => "not_permitted"})

      close_cleanly(device_channel)
    end

    test "an unknown mode is refused rather than crashing the connection", %{
      device: device,
      certificate: certificate
    } do
      device_channel = join_device(device, certificate, "2.4.0")
      assert_push("update_mode", %{"mode" => "automatic"})

      push(device_channel, "set_update_mode", %{"mode" => "whenever_i_feel_like_it"})

      assert_push("update_mode", %{"error" => "unknown_mode"})

      close_cleanly(device_channel)
    end

    test "check_update answers even when there is nothing to send", %{
      device: device,
      certificate: certificate
    } do
      device_channel = join_device(device, certificate, "2.4.0")
      assert_push("update_mode", _)

      push(device_channel, "check_update", %{})

      assert_push("update_available", %{"available" => false, "firmware_meta" => nil})

      close_cleanly(device_channel)
    end

    test "request_update is refused when the device has no deployment group", %{
      device: device,
      certificate: certificate
    } do
      device_channel = join_device(device, certificate, "2.4.0")
      assert_push("update_mode", _)

      push(device_channel, "request_update", %{})

      assert_push("update_rejected", %{"reason" => "no_deployment_group"})

      close_cleanly(device_channel)
    end

    test "a device too old to manage its own updates is put back on automatic", %{
      device: device,
      certificate: certificate,
      user: user
    } do
      {:ok, device} = Updates.set_update_mode(device, :device_managed, user)

      device_channel = join_device(device, certificate, "2.3.0")

      # It could neither be pushed to nor ask, so it would have sat on this
      # firmware indefinitely — most likely having auto-reverted onto it.
      assert Repo.reload(device).update_mode == :automatic

      assert [audit_log | _] = AuditLogs.logs_for(Repo.reload(device))
      assert audit_log.actor_type == Device
      assert audit_log.description =~ "returned to automatic updates"
      assert audit_log.description =~ "too old"

      close_cleanly(device_channel)
    end

    test "a failed revert is raised rather than swallowed", %{
      device: device,
      certificate: certificate,
      user: user
    } do
      {:ok, device} = Updates.set_update_mode(device, :device_managed, user)

      :ok =
        :telemetry.attach(
          "revert-failed-test",
          [:nerves_hub, :devices, :update_mode_revert_failed],
          fn _event, _measurements, metadata, pid -> send(pid, {:revert_failed, metadata}) end,
          self()
        )

      on_exit(fn -> :telemetry.detach("revert-failed-test") end)

      Mimic.stub(Updates, :revert_unsupported_update_mode, fn _device ->
        {:error, :update_with_audit, %Ecto.Changeset{}, %{}}
      end)

      device_channel = join_device(device, certificate, "2.3.0")

      # The device is still stranded, and would otherwise go on connecting as if
      # nothing were wrong, so it has to reach someone.
      assert_receive {:revert_failed, metadata}
      assert metadata.identifier == device.identifier

      assert [notification] = Repo.all(Notification)
      assert notification.product_id == device.product_id
      assert notification.level == :error
      assert notification.message =~ device.identifier

      close_cleanly(device_channel)
    end

    test "a device that can manage its own updates keeps the mode", %{
      device: device,
      certificate: certificate,
      user: user
    } do
      {:ok, device} = Updates.set_update_mode(device, :device_managed, user)

      device_channel = join_device(device, certificate, "2.4.0")

      assert Repo.reload(device).update_mode == :device_managed
      assert_push("update_mode", %{"mode" => "device_managed"})

      close_cleanly(device_channel)
    end

    test "an operator changing the mode reaches a connected device", %{
      device: device,
      certificate: certificate,
      user: user
    } do
      device_channel = join_device(device, certificate, "2.4.0")
      assert_push("update_mode", %{"mode" => "automatic", "managed_updates_allowed" => false})

      {:ok, _device} = Updates.set_managed_updates_allowed(device, true, user)

      assert_push("update_mode", %{"managed_updates_allowed" => true})

      close_cleanly(device_channel)
    end
  end

  defp join_device(device, certificate, device_api_version) do
    params =
      for {k, v} <- Map.from_struct(device.firmware_metadata), into: %{} do
        {"nerves_fw_#{k}", v}
      end

    params = Map.put(params, "device_api_version", device_api_version)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, %{}, device_channel} = subscribe_and_join(socket, DeviceChannel, "device:#{device.id}", params)

    device_channel
  end

  def device_fixture(user, device_params, tmp_dir, org \\ nil) do
    org = org || Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

    firmware =
      Fixtures.firmware_fixture(org_key, product, %{
        version: "0.0.1",
        dir: tmp_dir
      })

    deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})

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

  # Give the device's org one key of every other scheme, and return the fwup
  # key it already has. Neither an ESP-IDF RSA key nor a RAUC certificate is
  # something `fwup --public-key` can use, so neither may reach the device.
  defp seed_other_scheme_keys(device, user) do
    %OrgKey{key: fwup_key} = Repo.get_by!(OrgKey, org_id: device.org_id, scheme: :ed25519)

    {:ok, _esp_idf} =
      Accounts.create_org_key(%{
        org_id: device.org_id,
        created_by_id: user.id,
        name: "esp-idf",
        key: EspIdf.signing_public_key(),
        scheme: :secure_boot_v2_rsa
      })

    certificate =
      :secp256r1
      |> X509.PrivateKey.new_ec()
      |> X509.Certificate.self_signed("CN=rauc")
      |> X509.Certificate.to_pem()

    {:ok, _rauc} =
      Accounts.create_org_key(%{
        org_id: device.org_id,
        created_by_id: user.id,
        name: "rauc",
        key: certificate,
        scheme: :x509_certificate
      })

    fwup_key
  end

  defp archive_setup(tmp_dir) do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user, %{name: "BigOrg2022"})
    product = Fixtures.product_fixture(user, org, %{name: "Hop"})
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    archive = %{uuid: archive_uuid} = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})

    ManagedDeployments.create_deployment_release(
      deployment_group,
      firmware,
      archive,
      user,
      %{}
    )

    {device, _firmware, _deployment_group} =
      device_fixture(user, %{identifier: "123", deployment_id: deployment_group.id}, tmp_dir)

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

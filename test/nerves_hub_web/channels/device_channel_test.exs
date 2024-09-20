defmodule NervesHubWeb.DeviceChannelTest do
  use NervesHubWeb.ChannelCase
  use DefaultMocks

  import TrackerHelper

  alias NervesHub.Devices
  alias NervesHub.Fixtures
  alias NervesHubWeb.DeviceChannel
  alias NervesHubWeb.DeviceSocket

  test "basic connection to the channel" do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, socket} = subscribe_and_join(socket, DeviceChannel, "device")
    assert socket
    assert_push("check_health", %{})
  end

  test "detect multiple connections for the same device" do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, socket} = subscribe_and_join(socket, DeviceChannel, "device")
    assert socket

    {:ok, second_socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, second_socket} = subscribe_and_join(second_socket, DeviceChannel, "device")
    assert second_socket

    assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
  end

  describe "device location" do
    test "updates the device location" do
      user = Fixtures.user_fixture()
      {device, _firmware, _deployment} = device_fixture(user, %{identifier: "123"})
      %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

      {:ok, socket} =
        connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

      {:ok, _, socket} = subscribe_and_join(socket, DeviceChannel, "device")

      location_payload = %{"source" => "geoip", "latitude" => -41.29710, "longitude" => 174.79320}

      ref = push(socket, "location:update", location_payload)
      assert_reply(ref, :ok, %{})

      device = NervesHub.Repo.reload(device)

      assert device.connection_metadata["location"] == %{
               "source" => "geoip",
               "latitude" => -41.29710,
               "longitude" => 174.79320
             }
    end
  end

  test "presence connection information" do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    subscribe_for_updates(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, _socket} = subscribe_and_join(socket, DeviceChannel, "device")

    assert_connection_change()
  end

  test "fwup_public_keys requested on connect" do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment} = device_fixture(user, %{identifier: "123"})
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

    {:ok, %{}, _socket} = subscribe_and_join(socket, DeviceChannel, "device", params)

    assert_push("fwup_public_keys", %{keys: [_]})
  end

  test "archive_public_keys requested on connect" do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment} = device_fixture(user, %{identifier: "123"})
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

    {:ok, %{}, _socket} = subscribe_and_join(socket, DeviceChannel, "device", params)

    assert_push("archive_public_keys", %{keys: [_]})
  end

  test "devices can request available updates via check_update_available" do
    user = Fixtures.user_fixture()
    {device, _firmware, deployment} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    assert {:ok, device} = Devices.update_device(device, %{deployment_id: deployment.id})
    assert device.updates_enabled

    params =
      for {k, v} <- Map.from_struct(device.firmware_metadata), into: %{} do
        case k do
          :uuid -> {"nerves_fw_uuid", Ecto.UUID.generate()}
          _ -> {"nerves_fw_#{k}", v}
        end
      end

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, %{}, socket} = subscribe_and_join(socket, DeviceChannel, "device", params)

    ref = push(socket, "check_update_available", %{"value" => 10})

    assert_reply(ref, :ok, %NervesHub.Devices.UpdatePayload{update_available: true})
  end

  test "the first fwup_progress marks an update as happening" do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _join_reply, socket} =
      subscribe_and_join(socket, DeviceChannel, "device")

    push(socket, "fwup_progress", %{"value" => 10})

    # Since fwup_progress doesn't reply, we need to use sys to grab the socket
    # _after_ the handle_in has run
    socket = :sys.get_state(socket.channel_pid)
    assert socket.assigns.update_started?
  end

  test "set connection status upon connection and disconnection" do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    assert device.connection_status == :not_seen

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _join_reply, socket} =
      subscribe_and_join(socket, DeviceChannel, "device")

    device = NervesHub.Repo.reload(device)

    assert device.connection_status == :connected
    assert recent_datetime(device.connection_established_at)
    assert recent_datetime(device.connection_last_seen_at)
    assert device.connection_disconnected_at == nil

    Process.unlink(socket.channel_pid)
    :ok = close(socket)

    device = NervesHub.Repo.reload(device)

    assert device.connection_status == :disconnected
    assert recent_datetime(device.connection_established_at)
    assert recent_datetime(device.connection_last_seen_at)
    assert recent_datetime(device.connection_disconnected_at)
  end

  defp recent_datetime(datetime) do
    DateTime.diff(DateTime.utc_now(), datetime, :second) <= 5
  end

  test "set connection types for the device" do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _join_reply, socket} =
      subscribe_and_join(socket, DeviceChannel, "device")

    push(socket, "connection_types", %{"values" => ["ethernet", "wifi"]})

    # we need to let the channel process all messages before we can
    # check the state of the device's connection types
    _socket = :sys.get_state(socket.channel_pid)

    device = NervesHub.Repo.reload(device)
    assert device.connection_types == [:ethernet, :wifi]
  end

  test "deployment condition changing causes a deployment relookup" do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)

    firmware =
      Fixtures.firmware_fixture(org_key, product, %{
        version: "0.0.1"
      })

    deployment =
      Fixtures.deployment_fixture(org, firmware, %{
        conditions: %{"tags" => ["alpha"], "version" => ""}
      })

    {:ok, deployment} =
      NervesHub.Deployments.update_deployment(deployment, %{
        is_active: true
      })

    device_alpha =
      Fixtures.device_fixture(org, product, firmware, %{
        tags: ["alpha"],
        identifier: "123"
      })

    device_beta =
      Fixtures.device_fixture(org, product, firmware, %{
        tags: ["beta"],
        identifier: "234"
      })

    %{db_cert: alpha_certificate, cert: _cert} =
      Fixtures.device_certificate_fixture(device_alpha, X509.PrivateKey.new_ec(:secp256r1))

    {:ok, socket_alpha} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: alpha_certificate.der}})

    {:ok, %{}, socket_alpha} =
      subscribe_and_join(socket_alpha, DeviceChannel, "device")

    %{db_cert: beta_certificate, cert: _cert} =
      Fixtures.device_certificate_fixture(device_beta, X509.PrivateKey.new_ec(:secp256r1))

    {:ok, socket_beta} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: beta_certificate.der}})

    {:ok, %{}, socket_beta} =
      subscribe_and_join(socket_beta, DeviceChannel, "device")

    socket_alpha = :sys.get_state(socket_alpha.channel_pid)
    refute is_nil(socket_alpha.assigns.device.deployment_id)

    socket_beta = :sys.get_state(socket_beta.channel_pid)
    assert is_nil(socket_beta.assigns.device.deployment_id)

    # This will remove the deployment from alpha and
    # add it to the beta device
    {:ok, _deployment} =
      NervesHub.Deployments.update_deployment(deployment, %{
        conditions: %{"tags" => ["beta"]}
      })

    # skip the jitter
    send(socket_alpha.channel_pid, :resolve_changed_deployment)
    socket_alpha = :sys.get_state(socket_alpha.channel_pid)
    assert is_nil(socket_alpha.assigns.device.deployment_id)

    # skip the jitter
    send(socket_beta.channel_pid, :resolve_changed_deployment)
    socket_beta = :sys.get_state(socket_beta.channel_pid)
    refute is_nil(socket_beta.assigns.device.deployment_id)
  end

  test "deployment condition changing causes a deployment relookup but it still matches" do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)

    firmware =
      Fixtures.firmware_fixture(org_key, product, %{
        version: "0.0.1"
      })

    deployment =
      Fixtures.deployment_fixture(org, firmware, %{
        conditions: %{"tags" => ["alpha"], "version" => ""}
      })

    {:ok, deployment} =
      NervesHub.Deployments.update_deployment(deployment, %{
        is_active: true
      })

    device_alpha =
      Fixtures.device_fixture(org, product, firmware, %{
        tags: ["alpha", "device"],
        identifier: "123"
      })

    %{db_cert: alpha_certificate, cert: _cert} =
      Fixtures.device_certificate_fixture(device_alpha, X509.PrivateKey.new_ec(:secp256r1))

    {:ok, socket_alpha} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: alpha_certificate.der}})

    {:ok, %{}, socket_alpha} =
      subscribe_and_join(socket_alpha, DeviceChannel, "device")

    socket_alpha = :sys.get_state(socket_alpha.channel_pid)
    refute is_nil(socket_alpha.assigns.device.deployment_id)

    {:ok, _deployment} =
      NervesHub.Deployments.update_deployment(deployment, %{
        conditions: %{"tags" => ["alpha", "device"]}
      })

    socket_alpha = :sys.get_state(socket_alpha.channel_pid)
    refute is_nil(socket_alpha.assigns.device.deployment_id)
  end

  describe "unhandled messages are caught" do
    test "handle_info" do
      user = Fixtures.user_fixture()
      {device, _firmware, _deployment} = device_fixture(user, %{identifier: "123"})
      %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

      subscribe_for_updates(device)

      {:ok, socket} =
        connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

      {:ok, _join_reply, socket} =
        subscribe_and_join(socket, DeviceChannel, "device")

      send(socket.channel_pid, {"do_you_like_dem_apples", %{"apples" => 5}})

      assert_connection_change()
    end

    test "handle_in" do
      user = Fixtures.user_fixture()
      {device, _firmware, _deployment} = device_fixture(user, %{identifier: "123"})
      %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

      {:ok, socket} =
        connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

      {:ok, _join_reply, socket} =
        subscribe_and_join(socket, DeviceChannel, "device")

      ref = push(socket, "do_you_like_dem_apples", %{"apples" => 5})
      refute_reply(ref, %{})
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

    deployment = Fixtures.deployment_fixture(org, firmware)

    params = Enum.into(device_params, %{tags: ["beta", "beta-edge"]})

    device =
      Fixtures.device_fixture(
        org,
        product,
        firmware,
        params
      )

    {device, firmware, deployment}
  end
end

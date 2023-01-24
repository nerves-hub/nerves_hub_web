defmodule NervesHubDeviceWeb.DeviceChannelTest do
  use NervesHubDeviceWeb.ChannelCase
  use DefaultMocks
  alias NervesHubDeviceWeb.{DeviceSocket, DeviceChannel}
  alias NervesHubWebCore.{AuditLogs, Fixtures}
  alias NervesHubDevice.Presence

  test "basic connection to the channel" do
    user = Fixtures.user_fixture()
    {device, firmware, _deployment} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)
    {:ok, socket} = connect(DeviceSocket, %{}, %{peer_data: %{ssl_cert: certificate.der}})
    {:ok, _, socket} = subscribe_and_join(socket, DeviceChannel, "firmware:#{firmware.uuid}")
    assert socket
  end

  test "presence connection information" do
    user = Fixtures.user_fixture()
    {device, firmware, _deployment} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)
    {:ok, socket} = connect(DeviceSocket, %{}, %{peer_data: %{ssl_cert: certificate.der}})
    {:ok, _, _socket} = subscribe_and_join(socket, DeviceChannel, "firmware:#{firmware.uuid}")

    presence = Presence.find(device)
    assert presence.connected_at
    assert presence.last_communication
    assert presence.status == "online"
    assert presence.update_available == false
    assert presence.firmware_metadata
  end

  test "device disconnected adds audit log" do
    user = Fixtures.user_fixture()
    {device, firmware, _deployment} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)
    {:ok, socket} = connect(DeviceSocket, %{}, %{peer_data: %{ssl_cert: certificate.der}})
    {:ok, _, socket} = subscribe_and_join(socket, DeviceChannel, "firmware:#{firmware.uuid}")

    Process.unlink(socket.channel_pid)

    close(socket)

    disconnect_log =
      Enum.find(AuditLogs.logs_for(device), fn audit_log ->
        description = audit_log.changes["description"]
        description && description =~ "#{device.identifier} disconnected from the server at"
      end)

    assert disconnect_log
  end

  test "update_available on connect" do
    user = Fixtures.user_fixture()
    {device, firmware, _deployment} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)
    {:ok, socket} = connect(DeviceSocket, %{}, %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, join_reply, _socket} =
      subscribe_and_join(socket, DeviceChannel, "firmware:#{firmware.uuid}")

    assert join_reply.update_available == false
  end

  test "update_available after a firmware update" do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org)

    firmware =
      Fixtures.firmware_fixture(org_key, product, %{
        version: "0.0.1"
      })

    deployment = Fixtures.deployment_fixture(org, firmware)

    device =
      Fixtures.device_fixture(
        org,
        product,
        firmware,
        %{tags: ["beta", "beta-edge"], identifier: "123"}
      )

    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)
    {:ok, socket} = connect(DeviceSocket, %{}, %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, %{update_available: false}, _socket} =
      subscribe_and_join(socket, DeviceChannel, "firmware:#{firmware.uuid}")

    new_firmware =
      Fixtures.firmware_fixture(org_key, product, %{
        version: "0.0.2"
      })

    {:ok, _deployment} =
      NervesHubWebCore.Deployments.update_deployment(deployment, %{
        firmware_id: new_firmware.id,
        is_active: true
      })

    assert_push("update", %{firmware_meta: %{version: "0.0.2"}})
  end

  def device_fixture(user, device_params \\ %{}, org \\ nil) do
    org = org || Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org)

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

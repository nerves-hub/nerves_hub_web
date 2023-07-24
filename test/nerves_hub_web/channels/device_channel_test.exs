defmodule NervesHubWeb.DeviceChannelTest do
  use NervesHubWeb.ChannelCase
  use DefaultMocks

  alias NervesHub.AuditLogs
  alias NervesHub.Fixtures
  alias NervesHub.Tracker
  alias NervesHubWeb.DeviceChannel
  alias NervesHubWeb.DeviceSocket

  test "basic connection to the channel" do
    user = Fixtures.user_fixture()
    {device, firmware, _deployment} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, socket} = subscribe_and_join(socket, DeviceChannel, "firmware:#{firmware.uuid}")
    assert socket
  end

  test "presence connection information" do
    user = Fixtures.user_fixture()
    {device, firmware, _deployment} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, _socket} = subscribe_and_join(socket, DeviceChannel, "firmware:#{firmware.uuid}")

    assert Tracker.online?(device)
  end

  test "device disconnected adds audit log" do
    user = Fixtures.user_fixture()
    {device, firmware, _deployment} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, socket} = subscribe_and_join(socket, DeviceChannel, "firmware:#{firmware.uuid}")

    Process.unlink(socket.channel_pid)

    close(socket)

    disconnect_log =
      Enum.find(AuditLogs.logs_for(device), fn audit_log ->
        audit_log.description == "device #{device.identifier} disconnected from the server"
      end)

    assert disconnect_log
  end

  test "update_available on connect" do
    user = Fixtures.user_fixture()
    {device, firmware, _deployment} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, join_reply, _socket} =
      subscribe_and_join(socket, DeviceChannel, "firmware:#{firmware.uuid}")

    assert join_reply.update_available == false
  end

  test "the first fwup_progress marks an update as happening" do
    user = Fixtures.user_fixture()
    {device, firmware, _deployment} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _join_reply, socket} =
      subscribe_and_join(socket, DeviceChannel, "firmware:#{firmware.uuid}")

    push(socket, "fwup_progress", %{"value" => 10})

    # Since fwup_progress doesn't reply, we need to use sys to grab the socket
    # _after_ the handle_in has run
    socket = :sys.get_state(socket.channel_pid)
    assert socket.assigns.update_started?
  end

  test "set connection types for the device" do
    user = Fixtures.user_fixture()
    {device, firmware, _deployment} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _join_reply, socket} =
      subscribe_and_join(socket, DeviceChannel, "firmware:#{firmware.uuid}")

    push(socket, "connection_types", %{"value" => ["ethernet", "wifi"]})

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
    org_key = Fixtures.org_key_fixture(org)

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
        identifier: "123"
      })

    %{db_cert: alpha_certificate, cert: _cert} =
      Fixtures.device_certificate_fixture(device_alpha, X509.PrivateKey.new_ec(:secp256r1))

    {:ok, socket_alpha} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: alpha_certificate.der}})

    {:ok, %{update_available: false}, socket_alpha} =
      subscribe_and_join(socket_alpha, DeviceChannel, "device")

    %{db_cert: beta_certificate, cert: _cert} =
      Fixtures.device_certificate_fixture(device_beta, X509.PrivateKey.new_ec(:secp256r1))

    {:ok, socket_beta} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: beta_certificate.der}})

    {:ok, %{update_available: false}, socket_beta} =
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

    socket_beta = :sys.get_state(socket_beta.channel_pid)
    refute is_nil(socket_beta.assigns.device.deployment_id)
  end

  test "deployment condition changing causes a deployment relookup but it still matches" do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org)

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

    {:ok, %{update_available: false}, socket_alpha} =
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

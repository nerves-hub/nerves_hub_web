defmodule NervesHubWeb.DeviceChannelTest do
  use NervesHubWeb.ChannelCase
  use DefaultMocks

  import TrackerHelper

  alias NervesHub.Devices
  alias NervesHub.Fixtures
  alias NervesHubWeb.DeviceChannel
  alias NervesHubWeb.DeviceSocketCertAuth, as: DeviceSocket

  test "basic connection to the channel" do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, socket} = subscribe_and_join(socket, DeviceChannel, "device")
    assert socket
  end

  test "presence connection information" do
    user = Fixtures.user_fixture()
    {device, _firmware, _deployment} = device_fixture(user, %{identifier: "123"})
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    {:ok, _, _socket} = subscribe_and_join(socket, DeviceChannel, "device")

    assert_online(device)
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

  test "update_available on connect" do
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

    {:ok, %{}, _socket} = subscribe_and_join(socket, DeviceChannel, "device", params)

    assert_push("update", %{})
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

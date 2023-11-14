defmodule NervesHubWeb.DeviceChannelTest do
  use NervesHubWeb.ChannelCase
  use DefaultMocks

  alias NervesHub.Fixtures
  alias NervesHubWeb.DeviceChannel
  alias NervesHubWeb.DeviceSocket

  test "basic connection to the channel" do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org)
    firmware = Fixtures.firmware_fixture(org_key, product)
    device = Fixtures.device_fixture(org, product, firmware)
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    # Joins the channel
    assert {:ok, %{}, socket} = subscribe_and_join(socket, DeviceChannel, "device")
    assert socket

    # links with DeviceLink
    assert Process.alive?(socket.assigns.device_link_pid)

    # Incoming message doesn't crash
    push(socket, "fwup_progress", %{"value" => 10})

    # DeviceLink push_cb is correct
    push_cb = :sys.get_state(socket.assigns.device_link_pid).push_cb
    push_cb.("howdy", %{})
    assert_push("howdy", %{})

    # Socket close starts DeviceLink reconnect timer
    link = socket.assigns.device_link_pid
    Process.unlink(socket.channel_pid)
    close(socket)
    assert :sys.get_state(link).reconnect_timer
  end
end

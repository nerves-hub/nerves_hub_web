defmodule NervesHub.AWSIoTTest do
  use NervesHub.DataCase

  alias NervesHub.AWSIoT
  alias NervesHub.Devices.DeviceLink
  alias NervesHub.Fixtures
  alias NervesHub.Support.MQTTClient
  alias NervesHub.Tracker

  test "can publish to connected devices" do
    %{device: device} = create_device()
    {:ok, conn} = MQTTClient.start_link(device)
    topic = "nh/#{device.identifier}"

    assert MQTTClient.connected?(conn)
    assert MQTTClient.subscribed?(conn, topic)

    msg = %{event: "testing", payload: %{howdy: :partner}}

    AWSIoT.publish(device.identifier, msg.event, msg.payload)

    MQTTClient.assert_message(conn, topic, Jason.encode!(msg))
  end

  test "known device connection from lifecycle event" do
    %{device: device, device_certificate: cert} = create_device()
    refute Tracker.online?(device)
    refute DeviceLink.whereis(device)

    identifier = device.identifier

    lifecyle_event =
      %{
        clientId: device.identifier,
        timestamp: DateTime.to_unix(DateTime.utc_now()),
        eventType: :connected,
        sessionIdentifier: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower),
        principalIdentifier: Base.encode16(:crypto.hash(:sha256, cert.der), case: :lower),
        ipAddress: "127.0.0.2",
        versionNumber: 0
      }

    Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{identifier}:internal")

    # Publish message to the rule that forwards to the queue
    # This is expected to be configured in AWS to come from the broker
    PintBroker.publish(AWSIoT.PintBroker, "nh/device_messages", Jason.encode!(lifecyle_event))

    # Piggy back on internal messaging to know when status is updated to online
    assert_receive %{
      event: "connection_change",
      payload: %{device_id: ^identifier, status: "online"}
    }

    assert link = DeviceLink.whereis(device)
    # Do some minor halting work to let the tracker catch up
    _ = :sys.get_state(link)
    assert Tracker.online?(device)
  end

  test "unknown device connection from lifecyle event" do
    lifecyle_event = %{
      clientId: "im-an-imposter!",
      timestamp: DateTime.to_unix(DateTime.utc_now()),
      eventType: :connected,
      sessionIdentifier: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower),
      principalIdentifier: "123429083423094lskdf2304msd234",
      ipAddress: "127.0.0.2",
      versionNumber: 0
    }

    msg = %Broadway.Message{acknowledger: :stub, data: Jason.encode!(lifecyle_event)}

    # Assert on the broadway message sruct here to mostly test that things
    # don't crash in this case since there is no after effect
    assert %{status: {:failed, :unknown_device}} =
             AWSIoT.SQS.handle_message(:nerves_hub_iot_messages, msg, :no_context)
  end

  test "known device disconnect from lifecyle event" do
    %{device: device, device_certificate: cert} = create_device()
    assert {:ok, link} = DeviceLink.start_link(device)
    refute :sys.get_state(link).reconnect_timer
    identifier = device.identifier

    lifecyle_event =
      %{
        clientId: device.identifier,
        timestamp: DateTime.to_unix(DateTime.utc_now()),
        eventType: :disconnected,
        sessionIdentifier: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower),
        principalIdentifier: Base.encode16(:crypto.hash(:sha256, cert.der), case: :lower),
        clientInitiatedDisconnect: true,
        disconnectReason: "CLIENT_INITIATED_DISCONNECT",
        versionNumber: 0
      }

    Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{identifier}:internal")

    # Publish message to the rule that forwards to the queue
    # This is expected to be configured in AWS to come from the broker
    PintBroker.publish(AWSIoT.PintBroker, "nh/device_messages", Jason.encode!(lifecyle_event))

    # Piggy back on internal messaging to know when status is updated to online
    assert_receive %{
      event: "connection_change",
      payload: %{device_id: ^identifier, status: "offline"}
    }

    refute Tracker.online?(device)
    # DeviceLink starts a timer when told to disonnect so this is
    # an indirect way of checking it was called
    assert :sys.get_state(link).reconnect_timer
  end

  test "unknown device disconnect from lifecyle event" do
    data = %{
      clientId: "im-an-imposter!",
      timestamp: DateTime.to_unix(DateTime.utc_now()),
      eventType: :disconnected,
      sessionIdentifier: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower),
      principalIdentifier: "123429083423094lskdf2304msd234",
      clientInitiatedDisconnect: true,
      disconnectReason: "CLIENT_INITIATED_DISCONNECT",
      versionNumber: 0
    }

    msg = %Broadway.Message{acknowledger: :stub, data: Jason.encode!(data)}

    # Assert on the broadway message sruct here to mostly test that things
    # don't crash in this case since there is no after effect
    assert %{status: :ok} = AWSIoT.SQS.handle_message(:nerves_hub_iot_messages, msg, :no_context)
  end

  test "malformed messages from queue" do
    msg = %Broadway.Message{acknowledger: :stub, data: "i am invalid JSoN?!!*"}

    assert %{status: {:failed, :malformed}} =
             AWSIoT.SQS.handle_message(:nerves_hub_iot_messages, msg, :no_context)
  end

  test "unknown messages are ignored" do
    data = Jason.encode!(%{this: :is, an: :unhandled, message: "!"})
    msg = %Broadway.Message{acknowledger: :stub, data: data}
    assert %{status: :ok} = AWSIoT.SQS.handle_message(:nerves_hub_iot_messages, msg, :no_context)
  end

  defp create_device() do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org)
    firmware = Fixtures.firmware_fixture(org_key, product)

    device = Fixtures.device_fixture(org, product, firmware)

    %{db_cert: cert} =
      Fixtures.device_certificate_fixture(device, X509.PrivateKey.new_ec(:secp256r1))

    %{
      device: %{device | device_certificates: [cert]},
      device_certificate: cert,
      firmware: firmware,
      org: org,
      product: product,
      user: user
    }
  end
end

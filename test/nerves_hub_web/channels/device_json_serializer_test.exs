defmodule NervesHubWeb.Channels.DeviceJSONSerializerTest do
  use ExUnit.Case, async: true

  alias NervesHubWeb.Channels.DeviceJSONSerializer, as: Serializer
  alias Phoenix.Socket.Broadcast
  alias Phoenix.Socket.Message
  alias Phoenix.Socket.Reply

  describe "encode!/1" do
    test "strips the device id from a device topic" do
      message = %Message{
        join_ref: "1",
        ref: "2",
        topic: "device:456",
        event: "update",
        payload: %{"update_available" => true}
      }

      assert {:socket_push, :text, encoded} = Serializer.encode!(message)
      decoded = Jason.decode!(encoded)
      assert Enum.at(decoded, 2) == "device"
    end

    test "passes through non-device topics unchanged" do
      message = %Message{
        join_ref: nil,
        ref: nil,
        topic: "extensions",
        event: "hello",
        payload: %{}
      }

      assert {:socket_push, :text, encoded} = Serializer.encode!(message)
      decoded = Jason.decode!(encoded)
      assert Enum.at(decoded, 2) == "extensions"
    end

    test "strips the device id from a Reply topic" do
      reply = %Reply{
        join_ref: "1",
        ref: "1",
        topic: "device:789",
        status: :ok,
        payload: %{}
      }

      assert {:socket_push, :text, encoded} = Serializer.encode!(reply)
      decoded = Jason.decode!(encoded)
      assert Enum.at(decoded, 2) == "device"
    end
  end

  describe "fastlane!/1" do
    test "strips the device id from a Broadcast topic" do
      broadcast = %Broadcast{topic: "device:123", event: "archive", payload: %{"url" => "http://example.test"}}

      assert {:socket_push, :text, encoded} = Serializer.fastlane!(broadcast)
      decoded = Jason.decode!(encoded)
      assert Enum.at(decoded, 2) == "device"
    end

    test "passes through non-device broadcast topics unchanged" do
      broadcast = %Broadcast{topic: "some_other_topic", event: "ping", payload: %{}}

      assert {:socket_push, :text, encoded} = Serializer.fastlane!(broadcast)
      decoded = Jason.decode!(encoded)
      assert Enum.at(decoded, 2) == "some_other_topic"
    end
  end

  describe "decode!/2" do
    test "adds device_id from process dictionary back to the device topic" do
      Process.put(:device_id, 42)

      raw = Jason.encode!(["1", "1", "device", "phx_join", %{"token" => "abc"}])

      assert %Message{
               join_ref: "1",
               ref: "1",
               topic: "device:42",
               event: "phx_join",
               payload: %{"token" => "abc"}
             } = Serializer.decode!(raw, opcode: :text)
    end

    test "passes through non-device topics unchanged" do
      raw = Jason.encode!([nil, nil, "extensions", "hello", %{}])

      assert %Message{topic: "extensions"} = Serializer.decode!(raw, opcode: :text)
    end
  end

  test "a Message survives an encode!/decode! round trip" do
    Process.put(:device_id, 99)

    original = %Message{
      join_ref: "3",
      ref: "4",
      topic: "device:99",
      event: "update",
      payload: %{"firmware_url" => "http://example.test/fw.fw"}
    }

    {:socket_push, :text, encoded} = Serializer.encode!(original)
    decoded = Serializer.decode!(encoded, opcode: :text)

    assert decoded.join_ref == original.join_ref
    assert decoded.ref == original.ref
    assert decoded.topic == original.topic
    assert decoded.event == original.event
    assert decoded.payload == original.payload
  end
end

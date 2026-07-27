defmodule NervesHubWeb.Channels.DeviceMsgPackSerializerTest do
  use ExUnit.Case, async: true

  alias NervesHubWeb.Channels.DeviceMsgPackSerializer, as: Serializer
  alias Phoenix.Socket.Broadcast
  alias Phoenix.Socket.Message
  alias Phoenix.Socket.Reply

  describe "encode!/1" do
    test "encodes a Message as a binary MessagePack envelope" do
      message = %Message{
        join_ref: "1",
        ref: "2",
        topic: "device:123",
        event: "update",
        payload: %{"update_available" => true}
      }

      assert {:socket_push, :binary, encoded} = Serializer.encode!(message)

      assert Msgpax.unpack!(encoded) == [
               "1",
               "2",
               # the device id is stripped back to the deprecated topic on the way out
               "device",
               "update",
               %{"update_available" => true}
             ]
    end

    test "encodes a Reply with its status and response wrapped in the envelope" do
      reply = %Reply{
        join_ref: "1",
        ref: "1",
        topic: "device:123",
        status: :ok,
        payload: %{"foo" => "bar"}
      }

      assert {:socket_push, :binary, encoded} = Serializer.encode!(reply)

      assert Msgpax.unpack!(encoded) == [
               "1",
               "1",
               "device",
               "phx_reply",
               %{"status" => "ok", "response" => %{"foo" => "bar"}}
             ]
    end

    test "leaves non-device topics untouched" do
      message = %Message{join_ref: nil, ref: nil, topic: "extensions", event: "hello", payload: %{}}

      assert {:socket_push, :binary, encoded} = Serializer.encode!(message)
      assert [nil, nil, "extensions", "hello", %{}] = Msgpax.unpack!(encoded)
    end
  end

  describe "fastlane!/1" do
    test "encodes a Broadcast with nil refs and the device id stripped" do
      broadcast = %Broadcast{topic: "device:123", event: "archive", payload: %{"url" => "http://example.test"}}

      assert {:socket_push, :binary, encoded} = Serializer.fastlane!(broadcast)

      assert Msgpax.unpack!(encoded) == [
               nil,
               nil,
               "device",
               "archive",
               %{"url" => "http://example.test"}
             ]
    end
  end

  describe "decode!/2" do
    test "decodes a binary MessagePack envelope into a Message" do
      # the device subscribes to the deprecated `device` topic; the serializer
      # rewrites it to `device:<id>` using the id stashed in the process dictionary
      Process.put(:device_id, 123)

      encoded = Msgpax.pack!(["1", "1", "device", "phx_join", %{"foo" => "bar"}], iodata: false)

      assert %Message{
               join_ref: "1",
               ref: "1",
               topic: "device:123",
               event: "phx_join",
               payload: %{"foo" => "bar"}
             } = Serializer.decode!(encoded, opcode: :binary)
    end

    test "keeps nil refs as nil and leaves non-device topics untouched" do
      encoded = Msgpax.pack!([nil, nil, "extensions", "hello", %{}], iodata: false)

      assert %Message{join_ref: nil, ref: nil, topic: "extensions", event: "hello", payload: %{}} =
               Serializer.decode!(encoded, opcode: :binary)
    end
  end

  test "a Message survives an encode!/decode! round trip" do
    Process.put(:device_id, 123)

    original = %Message{
      join_ref: "7",
      ref: "8",
      topic: "device:123",
      event: "connection_types",
      payload: %{"values" => ["ethernet", "wifi"]}
    }

    {:socket_push, :binary, encoded} = Serializer.encode!(original)
    decoded = Serializer.decode!(encoded, opcode: :binary)

    assert decoded.join_ref == original.join_ref
    assert decoded.ref == original.ref
    assert decoded.topic == original.topic
    assert decoded.event == original.event
    assert decoded.payload == original.payload
  end
end

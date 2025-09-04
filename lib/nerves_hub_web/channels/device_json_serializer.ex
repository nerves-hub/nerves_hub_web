defmodule NervesHubWeb.Channels.DeviceJSONSerializer do
  @moduledoc """
  A pass-through JSON serializer which updates the topic of the messages sent to the device,
  conforming to the old (deprecated) topic expected by NervesHubLink, but allowing us to
  use fastlaning of pubsub messages.

  Devices subscribe to the `device` topic, but within `DeviceChannel` we unsubscribe from that
  topic and setup a new `device:[device_id]` subscription for the channel, which allows us
  to take advantage of sending messages directly to the device without having to have
  `DeviceChannel` intercept, modify, and push the message to the device.

  eg. `%Phoenix.Socket.Broadcast{topic: "device:123", event: "identify", payload: %{}}`
        => `%Phoenix.Socket.Broadcast{topic: "device", event: "identify", payload: %{}}`
  """
  @behaviour Phoenix.Socket.Serializer

  @push 0

  alias Phoenix.Socket.Message

  @impl Phoenix.Socket.Serializer
  def fastlane!(msg) do
    msg
    |> remove_device_id_from_topic()
    |> Phoenix.Socket.V2.JSONSerializer.fastlane!()
  end

  @impl Phoenix.Socket.Serializer
  def encode!(reply) do
    reply
    |> remove_device_id_from_topic()
    |> Phoenix.Socket.V2.JSONSerializer.encode!()
  end

  @impl Phoenix.Socket.Serializer
  def decode!(raw_message, opts) do
    case Keyword.fetch(opts, :opcode) do
      {:ok, :text} -> decode_text(raw_message)
      {:ok, :binary} -> decode_binary(raw_message)
    end
    |> add_device_id_to_topic()
  end

  defp decode_text(raw_message) do
    [join_ref, ref, topic, event, payload | _] = Phoenix.json_library().decode!(raw_message)

    %Message{
      topic: topic,
      event: event,
      payload: payload,
      ref: ref,
      join_ref: join_ref
    }
  end

  defp decode_binary(
         <<@push::size(8), join_ref_size::size(8), ref_size::size(8), topic_size::size(8), event_size::size(8),
           join_ref::binary-size(join_ref_size), ref::binary-size(ref_size), topic::binary-size(topic_size),
           event::binary-size(event_size), data::binary>>
       ) do
    %Message{
      topic: topic,
      event: event,
      payload: {:binary, data},
      ref: ref,
      join_ref: join_ref
    }
  end

  defp remove_device_id_from_topic(msg) do
    if String.starts_with?(msg.topic, "device:") do
      [topic | _device_id] = String.split(msg.topic, ":")
      %{msg | topic: topic}
    else
      msg
    end
  end

  defp add_device_id_to_topic(msg) do
    if msg.topic == "device" && !String.starts_with?(msg.event, "phx_") && msg.event != "heartbeat" do
      %{msg | topic: "device:#{Process.get(:device_id)}"}
    else
      msg
    end
  end
end

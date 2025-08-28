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

  @impl Phoenix.Socket.Serializer
  def fastlane!(msg) do
    msg
    |> update_topic()
    |> Phoenix.Socket.V2.JSONSerializer.fastlane!()
  end

  @impl Phoenix.Socket.Serializer
  def encode!(reply) do
    reply
    |> update_topic()
    |> Phoenix.Socket.V2.JSONSerializer.encode!()
  end

  @impl Phoenix.Socket.Serializer
  defdelegate decode!(raw_message, opts), to: Phoenix.Socket.V2.JSONSerializer

  defp update_topic(msg) do
    if String.starts_with?(msg.topic, "device:") do
      [topic | _device_id] = String.split(msg.topic, ":")
      %{msg | topic: topic}
    else
      msg
    end
  end
end

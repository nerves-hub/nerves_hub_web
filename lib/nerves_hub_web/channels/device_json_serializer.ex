defmodule NervesHubWeb.Channels.DeviceJSONSerializer do
  @moduledoc """
  A pass-through JSON serializer which updates the topic of the messages received from, and
  sent to the device, conforming to the old (deprecated) topic expected by NervesHubLink,
  but allowing us to use fastlaning of pubsub messages.

  This allows us to leave NervesHubLink as it is, but switch the topic it subscribes so.

  `device` => `device:[device_id]`

  This allows us to take advantage of sending messages directly to the device without having to
  have `DeviceChannel` intercept, modify, and push the message to the device.

  And when sending messages to the device, we can use the `DeviceJSONSerializer` to update the topic
  to conform to the old (deprecated) topic expected by NervesHubLink.

  `device:[device_id]` => `device`
  """
  @behaviour Phoenix.Socket.Serializer

  alias Phoenix.Socket.Serializer
  alias Phoenix.Socket.V2.JSONSerializer

  @impl Serializer
  def fastlane!(msg) do
    msg
    |> remove_device_id_from_topic()
    |> JSONSerializer.fastlane!()
  end

  @impl Serializer
  def encode!(reply) do
    reply
    |> remove_device_id_from_topic()
    |> JSONSerializer.encode!()
  end

  @impl Serializer
  def decode!(raw_message, opts) do
    JSONSerializer.decode!(raw_message, opts)
    |> add_device_id_to_topic()
  end

  defp remove_device_id_from_topic(%{topic: "device:" <> _} = msg) do
    %{msg | topic: "device"}
  end

  defp remove_device_id_from_topic(msg), do: msg

  defp add_device_id_to_topic(%{topic: "device"} = msg) do
    %{msg | topic: "device:#{Process.get(:device_id)}"}
  end

  defp add_device_id_to_topic(msg), do: msg
end

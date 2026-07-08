defmodule NervesHubWeb.Channels.DeviceMsgPackSerializer do
  @behaviour Phoenix.Socket.Serializer

  alias Phoenix.Socket.Broadcast
  alias Phoenix.Socket.Message
  alias Phoenix.Socket.Reply
  alias Phoenix.Socket.Serializer

  @impl Serializer
  def fastlane!(%Broadcast{} = msg) do
    envelope = [nil, nil, remove_device_id_from_topic(msg.topic), msg.event, msg.payload]
    {:ok, encoded_envelope} = Msgpax.pack(envelope, iodata: false)
    {:socket_push, :binary, encoded_envelope}
  end

  @impl Serializer
  def encode!(%Reply{} = reply) do
    envelope = [
      reply.join_ref,
      reply.ref,
      remove_device_id_from_topic(reply.topic),
      "phx_reply",
      %{status: reply.status, response: reply.payload}
    ]

    {:ok, encoded_envelope} = Msgpax.pack(envelope, iodata: false)

    {:socket_push, :binary, encoded_envelope}
  end

  def encode!(%Message{} = msg) do
    envelope = [msg.join_ref, msg.ref, remove_device_id_from_topic(msg.topic), msg.event, msg.payload]
    {:ok, encoded_envelope} = Msgpax.pack(envelope, iodata: false)
    {:socket_push, :binary, encoded_envelope}
  end

  @impl Serializer
  def decode!(encoded_envelope, opts) do
    case Keyword.fetch!(opts, :opcode) do
      :binary ->
        {:ok, envelope} = Msgpax.unpack(encoded_envelope)

        [join_ref, ref, topic, event, payload] = envelope

        %Message{
          join_ref: to_ref_string(join_ref),
          ref: to_ref_string(ref),
          topic: add_device_id_to_topic(topic),
          event: event,
          payload: payload
        }
    end
  end

  defp to_ref_string(nil), do: nil
  defp to_ref_string(ref), do: to_string(ref)

  defp remove_device_id_from_topic("device:" <> _), do: "device"
  defp remove_device_id_from_topic(msg), do: msg

  defp add_device_id_to_topic("device"), do: "device:#{Process.get(:device_id)}"
  defp add_device_id_to_topic(msg), do: msg
end

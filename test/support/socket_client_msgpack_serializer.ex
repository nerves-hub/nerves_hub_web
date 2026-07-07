defmodule SocketClient.MsgpackSerializer do
  @moduledoc """
  A client-side (Slipstream) MessagePack serializer which matches the wire format
  of the server-side `NervesHubWeb.Channels.DeviceMsgPackSerializer`.

  Messages are packed as a 5-element array `[join_ref, ref, topic, event, payload]`
  and sent as binary frames, mirroring the Phoenix v2 array layout but using
  MessagePack instead of JSON.

  This lets the websocket tests exercise the same MessagePack path a device using
  the `~> 3.0.0` serializer version would use.
  """

  @behaviour Slipstream.Serializer

  alias Slipstream.Message

  @impl Slipstream.Serializer
  def encode!(%Message{} = message, _opts) do
    envelope = [message.join_ref, message.ref, message.topic, message.event, message.payload]
    {:binary, Msgpax.pack!(envelope, iodata: false)}
  end

  @impl Slipstream.Serializer
  def decode!(encoded, opts) do
    case Keyword.fetch!(opts, :opcode) do
      :binary ->
        [join_ref, ref, topic, event, payload] = Msgpax.unpack!(encoded)

        %Message{
          join_ref: join_ref,
          ref: ref,
          topic: topic,
          event: event,
          payload: payload
        }
    end
  end
end

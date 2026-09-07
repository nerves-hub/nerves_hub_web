defmodule SocketClient.LegacyJoinRefMsgpackSerializer do
  @moduledoc """
  The MessagePack counterpart of `SocketClient.LegacyJoinRefSerializer`: it
  drops the `join_ref` from every message except `phx_join`, so the legacy
  client behaviour is exercised against both device wire formats.
  """

  @behaviour Slipstream.Serializer

  alias Slipstream.Message

  @impl Slipstream.Serializer
  def encode!(%Message{event: "phx_join"} = message, opts) do
    SocketClient.MsgpackSerializer.encode!(message, opts)
  end

  def encode!(%Message{} = message, opts) do
    SocketClient.MsgpackSerializer.encode!(%{message | join_ref: nil}, opts)
  end

  @impl Slipstream.Serializer
  def decode!(encoded, opts), do: SocketClient.MsgpackSerializer.decode!(encoded, opts)
end

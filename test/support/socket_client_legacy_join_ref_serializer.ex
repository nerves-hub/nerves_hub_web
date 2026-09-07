defmodule SocketClient.LegacyJoinRefSerializer do
  @moduledoc """
  A client-side (Slipstream) JSON serializer which mimics older Slipstream
  releases: they only sent a `join_ref` on `phx_join` and left it `nil` on every
  subsequent message (CuatroElixir/slipstream#84).

  Plenty of deployed devices still run those releases, so the server has to keep
  accepting their messages. Phoenix 1.8.12 does (phoenixframework/phoenix#6800),
  which is what let us drop the `join_ref` bandaid from
  `NervesHubWeb.DeviceSocket`. This keeps such a device on the wire in the test
  suite, so we'd notice if that tolerance ever went away again.
  """

  @behaviour Slipstream.Serializer

  alias Slipstream.Message
  alias Slipstream.Serializer.PhoenixSocketV2Serializer

  @impl Slipstream.Serializer
  def encode!(%Message{event: "phx_join"} = message, opts) do
    PhoenixSocketV2Serializer.encode!(message, opts)
  end

  def encode!(%Message{} = message, opts) do
    PhoenixSocketV2Serializer.encode!(%{message | join_ref: nil}, opts)
  end

  @impl Slipstream.Serializer
  def decode!(encoded, opts), do: PhoenixSocketV2Serializer.decode!(encoded, opts)
end

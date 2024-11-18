defmodule NervesHub.FeaturesSerializer do
  @behaviour Phoenix.Socket.Serializer

  alias Phoenix.Socket.V2.JSONSerializer

  @impl Phoenix.Socket.Serializer
  def decode!(iodata, opts) do
    JSONSerializer.decode!(iodata, opts)
  end

  @impl Phoenix.Socket.Serializer
  def encode!(arg1) do
    JSONSerializer.encode!(arg1)
  end

  @impl Phoenix.Socket.Serializer
  def fastlane!(broadcast) do
    JSONSerializer.fastlane!(broadcast)
  end
end

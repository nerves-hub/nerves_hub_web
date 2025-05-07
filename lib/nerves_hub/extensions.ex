defmodule NervesHub.Extensions do
  @moduledoc """
  An "extension" is an additional piece of functionality that we add onto the
  existing connection between the device and the NervesHub service. They are
  designed to be less important than firmware updates and requires both client
  to report support and the server to enable support.

  This is intended to ensure that:

  - The service decides when activity should be taken by the device meaning
    the fleet of devices will not inadvertently swarm the service with data.
  - The service can turn off extensions in various ways to ensure that disruptive
    extensions stop being enabled on subsequent connections.
  - Use of extensions should have very little chance to disrupt the flow of a
    critical firmware update.
  """

  @callback handle_in(event :: String.t(), Phoenix.Channel.payload(), Phoenix.Socket.t()) ::
              {:noreply, Phoenix.Socket.t()}
              | {:noreply, Phoenix.Socket.t(), timeout() | :hibernate}
              | {:reply, Phoenix.Channel.reply(), Phoenix.Socket.t()}
              | {:stop, reason :: term(), Phoenix.Socket.t()}
              | {:stop, reason :: term(), Phoenix.Channel.reply(), Phoenix.Socket.t()}

  @callback handle_info(msg :: term(), Phoenix.Socket.t()) ::
              {:noreply, Phoenix.Socket.t()} | {:stop, reason :: term(), Phoenix.Socket.t()}

  @callback attach(Phoenix.Socket.t()) :: {:noreply, Phoenix.Socket.t()}
  @callback detach(Phoenix.Socket.t()) :: {:noreply, Phoenix.Socket.t()}
  @callback description() :: String.t()
  @callback enabled?() :: boolean()

  require Logger

  @supported_extensions [:health, :geo, :logging]
  @type extension() :: :health | :geo | :logging

  @doc """
  Get list of supported extensions as atoms with descriptive text.
  """
  @spec list() :: [:geo | :health | :logging, ...]
  def list(), do: @supported_extensions

  @spec module(extension()) ::
          NervesHub.Extensions.Geo | NervesHub.Extensions.Health | NervesHub.Extensions.Logging
  def module(:geo), do: NervesHub.Extensions.Geo
  def module(:health), do: NervesHub.Extensions.Health
  def module(:logging), do: NervesHub.Extensions.Logging

  @spec module(extension(), Version.t()) :: module() | NervesHub.Extensions.Unsupported
  def module(:health, ver) do
    cond do
      Version.match?(ver, "~> 0.0.1") -> NervesHub.Extensions.Health
      true -> NervesHub.Extensions.Unsupported
    end
  end

  def module(:geo, ver) do
    cond do
      Version.match?(ver, "~> 0.0.1") -> NervesHub.Extensions.Geo
      true -> NervesHub.Extensions.Unsupported
    end
  end

  def module(:logging, ver) do
    cond do
      Version.match?(ver, "~> 0.0.1") -> NervesHub.Extensions.Logging
      true -> NervesHub.Extensions.Unsupported
    end
  end

  def module(_key, _ver) do
    NervesHub.Extensions.Unsupported
  end

  def broadcast_extension_event(target, event, extension) do
    Phoenix.Channel.Server.broadcast_from!(
      NervesHub.PubSub,
      self(),
      topic(target),
      event,
      %{
        "extensions" => [extension]
      }
    )
  end

  defp topic(%NervesHub.Devices.Device{} = device), do: "device:#{device.id}:extensions"
  defp topic(%NervesHub.Products.Product{} = product), do: "product:#{product.id}:extensions"
end

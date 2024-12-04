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

  require Logger

  @supported_extensions [:health, :geo]
  @type extension() :: :health | :geo

  @doc """
  Get list of supported extensions as atoms with descriptive text.
  """
  @spec list() :: list(extension())
  def list do
    @supported_extensions
  end

  @spec module(extension()) :: module() | :unsupported
  def module(:health), do: NervesHub.Extensions.Health
  def module(:geo), do: NervesHub.Extensions.Geo
  def module(_key), do: :unsupported

  @spec module(extension(), Version.t()) :: module() | :unsupported
  def module(:health, ver) do
    cond do
      Version.match?(ver, "~> 0.0.1") -> NervesHub.Extensions.Health
      true -> :unsupported
    end
  end

  def module(:geo, ver) do
    cond do
      Version.match?(ver, "~> 0.0.1") -> NervesHub.Extensions.Geo
      true -> :unsupported
    end
  end

  def module(_key, _ver) do
    :unsupported
  end
end

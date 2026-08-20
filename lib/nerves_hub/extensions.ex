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

  alias NervesHub.Devices.Device
  alias NervesHub.Extensions.ExternalIdentity
  alias NervesHub.Extensions.Geo
  alias NervesHub.Extensions.Health
  alias NervesHub.Extensions.LocalShell
  alias NervesHub.Extensions.Logging
  alias NervesHub.Extensions.State
  alias NervesHub.Extensions.Unsupported
  alias NervesHub.Products.Product
  alias Phoenix.Channel.Server, as: ChannelServer

  @typedoc """
  What every extension callback returns: the extension's new state, plus any
  effects for the caller to carry out on the device connection.

  See `NervesHub.Extensions.State` for why extensions no longer take a
  `Phoenix.Socket`.
  """
  @type result() :: {State.t(), [State.effect()]}

  @callback handle_in(event :: String.t(), Phoenix.Channel.payload(), State.t()) :: result()

  @callback handle_info(msg :: term(), State.t()) :: result()

  @callback attach(State.t()) :: result()
  @callback detach(State.t()) :: result()
  @callback description() :: String.t()
  @callback enabled?() :: boolean()

  @supported_extensions [:health, :geo, :local_shell, :logging, :external_identity]
  @type extension() :: :health | :geo | :local_shell | :logging | :external_identity

  @doc """
  Get list of supported extensions as atoms with descriptive text.
  """
  @spec list() :: [:external_identity | :geo | :health | :local_shell | :logging, ...]
  def list(), do: @supported_extensions

  @spec module(extension()) ::
          ExternalIdentity
          | Geo
          | Health
          | LocalShell
          | Logging
  def module(:geo), do: Geo
  def module(:health), do: Health
  def module(:local_shell), do: LocalShell
  def module(:logging), do: Logging
  def module(:external_identity), do: ExternalIdentity

  @spec module(extension(), Version.t()) :: module() | Unsupported
  def module(:health, ver) do
    if Version.match?(ver, "~> 0.0.1") do
      Health
    else
      Unsupported
    end
  end

  def module(:geo, ver) do
    if Version.match?(ver, "~> 0.0.1") do
      Geo
    else
      Unsupported
    end
  end

  def module(:local_shell, ver) do
    if Version.match?(ver, "~> 0.0.1") do
      LocalShell
    else
      Unsupported
    end
  end

  def module(:logging, ver) do
    if Version.match?(ver, "~> 0.0.1") do
      Logging
    else
      Unsupported
    end
  end

  def module(:external_identity, ver) do
    if Version.match?(ver, "~> 0.0.1") do
      ExternalIdentity
    else
      Unsupported
    end
  end

  def module(_key, _ver) do
    Unsupported
  end

  def broadcast_extension_event(target, event, extension) do
    ChannelServer.broadcast_from!(
      NervesHub.PubSub,
      self(),
      topic(target),
      event,
      %{
        "extensions" => [extension]
      }
    )
  end

  defp topic(%Device{} = device), do: "device:#{device.id}:extensions"
  defp topic(%Product{} = product), do: "product:#{product.id}:extensions"
end

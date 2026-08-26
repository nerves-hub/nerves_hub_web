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
  alias NervesHub.Extensions.Geo
  alias NervesHub.Extensions.Health
  alias NervesHub.Extensions.LocalShell
  alias NervesHub.Extensions.Logging
  alias NervesHub.Extensions.NetworkIdentity
  alias NervesHub.Extensions.PubSub
  alias NervesHub.Extensions.State
  alias NervesHub.Extensions.Unsupported
  alias NervesHub.Products.Product

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

  @supported_extensions [:health, :geo, :local_shell, :logging, :network_identity]
  @type extension() :: :health | :geo | :local_shell | :logging | :network_identity

  @doc """
  Get list of supported extensions as atoms with descriptive text.
  """
  @spec list() :: [:network_identity | :geo | :health | :local_shell | :logging, ...]
  def list(), do: @supported_extensions

  @spec module(extension()) ::
          NetworkIdentity
          | Geo
          | Health
          | LocalShell
          | Logging
  def module(:geo), do: Geo
  def module(:health), do: Health
  def module(:local_shell), do: LocalShell
  def module(:logging), do: Logging
  def module(:network_identity), do: NetworkIdentity

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

  # Two extensions, one key. 0.0.x sends one log line per message; 0.1.x puts a
  # second's worth in one, which is what lets a device stop paying a message
  # per line. A device gets the module for the version it declared, so both
  # keep working and neither has to know about the other.
  def module(:logging, ver) do
    cond do
      Version.match?(ver, "~> 0.0.1") -> Logging
      Version.match?(ver, "~> 0.1.0") -> Logging.Batched
      true -> Unsupported
    end
  end

  def module(:network_identity, ver) do
    if Version.match?(ver, "~> 0.0.1") do
      NetworkIdentity
    else
      Unsupported
    end
  end

  def module(_key, _ver) do
    Unsupported
  end

  def broadcast_extension_event(%Device{} = device, event, extension) do
    # web -> device: only the device's extensions channel consumes this.
    PubSub.broadcast_to_device(device, event, %{"extensions" => [extension]})
  end

  def broadcast_extension_event(%Product{} = product, event, extension) do
    # Product-wide fan-out to every device's extensions channel stays on
    # Phoenix.PubSub (dense fan-out, no targeted-dispatch win); routed through
    # the wrapper for consistency with the per-device path.
    PubSub.broadcast_to_product(product.id, event, %{"extensions" => [extension]})
  end
end

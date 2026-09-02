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
  alias NervesHub.Devices.DeviceMessages
  alias NervesHub.Extensions.Components
  alias NervesHub.Extensions.ErrorReports
  alias NervesHub.Extensions.Geo
  alias NervesHub.Extensions.Health
  alias NervesHub.Extensions.LocalShell
  alias NervesHub.Extensions.Logging
  alias NervesHub.Extensions.Metrics
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

  @typedoc """
  Every version of every extension this platform implements.

  Ordered newest first per key, and the single place a version is written down:
  `module/2` reads it to serve a device, `versions/1` and `advertisement/0` read
  it to tell devices what is on offer. Adding a version means adding a row here
  and nothing else.

  Each row is `{advertised, requirement, module}`:

  - `advertised` is the exact version a device may declare, and what goes out
    in `extensions:get`.
  - `requirement` is what a device's declared version is matched against, which
    is looser than the advertised version on purpose: a device declaring
    `0.0.5` predates the advertisement and still has to be served.
  - `module` implements that version of the extension.
  """
  @type implementation() :: {String.t(), String.t(), module()}

  @implementations [
    health: [{"0.0.1", "~> 0.0.1", Health}],
    metrics: [{"0.1.0", "~> 0.1.0", Metrics}],
    geo: [{"0.0.1", "~> 0.0.1", Geo}],
    local_shell: [{"0.0.1", "~> 0.0.1", LocalShell}],
    logging: [
      {"0.1.0", "~> 0.1.0", Logging.Batched},
      {"0.0.1", "~> 0.0.1", Logging}
    ],
    network_identity: [{"0.0.1", "~> 0.0.1", NetworkIdentity}],
    error_reports: [{"0.1.0", "~> 0.1.0", ErrorReports}],
    components: [{"0.0.1", "~> 0.0.1", Components}]
  ]

  @supported_extensions Keyword.keys(@implementations)
  @type extension() ::
          :health
          | :metrics
          | :geo
          | :local_shell
          | :logging
          | :network_identity
          | :error_reports
          | :components

  @doc """
  Get list of supported extensions as atoms with descriptive text.
  """
  @spec list() :: [extension(), ...]
  def list(), do: @supported_extensions

  @doc """
  Every version of `key` this platform implements, newest first.
  """
  @spec versions(extension()) :: [String.t()]
  def versions(key) do
    for {version, _requirement, _module} <- implementations(key), do: version
  end

  @doc """
  What to tell a device it can have, as `%{key => versions}`.

  Sent in `extensions:get` so that a device implementing more than one version
  of an extension can declare the best one both sides have, rather than naming
  a version before it knows anything about the platform and finding out from
  the attach list whether it guessed right.

  Extensions that are switched off for this deployment are left out entirely: a
  device that is not told about logging does not buffer log lines for a
  platform that would throw them away.

  Not narrowed to one device. Whether a *particular* device may use an
  extension is a product and device setting, and it stays where it already is,
  in the attach list — one authority for that, and nothing for a device to act
  on that a later setting change would contradict.
  """
  @spec advertisement() :: %{String.t() => [String.t()]}
  def advertisement() do
    for {key, implementations} <- @implementations,
        versions = enabled_versions(implementations),
        versions != [],
        into: %{},
        do: {to_string(key), versions}
  end

  @spec module(extension()) ::
          NetworkIdentity
          | Components
          | ErrorReports
          | Geo
          | Health
          | LocalShell
          | Logging
          | Metrics
  def module(:components), do: Components
  def module(:error_reports), do: ErrorReports
  def module(:geo), do: Geo
  def module(:health), do: Health
  def module(:metrics), do: Metrics
  def module(:local_shell), do: LocalShell
  def module(:logging), do: Logging
  def module(:network_identity), do: NetworkIdentity

  @doc """
  The module that serves `key` for a device that declared `ver`.

  `Unsupported` when this platform has no version matching what the device
  asked for, which leaves the extension out of the attach list. That is the
  answer a device can see and report; attaching it to whichever module was
  closest would have the device sending messages nothing can read.
  """
  @spec module(extension(), Version.t()) :: module()
  def module(key, ver) do
    Enum.find_value(implementations(key), Unsupported, fn {_advertised, requirement, module} ->
      Version.match?(ver, requirement) && module
    end)
  end

  defp implementations(key) when is_atom(key), do: Keyword.get(@implementations, key, [])
  defp implementations(_key), do: []

  defp enabled_versions(implementations) do
    for {version, _requirement, module} <- implementations,
        Code.ensure_loaded?(module) && module.enabled?(),
        do: version
  end

  def broadcast_extension_event(%Device{} = device, event, extension) do
    payload = %{"extensions" => [extension]}

    # Recorded here, where the message is produced, rather than in the channel
    # that pushes it: that channel is not always on a node with a database. See
    # `NervesHub.Extensions.PubSub` on why the recording is not in the wrapper.
    :ok = DeviceMessages.record(device, :sent, :extensions, event, payload)

    # web -> device: only the device's extensions channel consumes this.
    PubSub.broadcast_to_device(device.id, event, payload)
  end

  def broadcast_extension_event(%Product{} = product, event, extension) do
    # Product-wide fan-out to every device's extensions channel stays on
    # Phoenix.PubSub (dense fan-out, no targeted-dispatch win); routed through
    # the wrapper for consistency with the per-device path.
    PubSub.broadcast_to_product(product.id, event, %{"extensions" => [extension]})
  end
end

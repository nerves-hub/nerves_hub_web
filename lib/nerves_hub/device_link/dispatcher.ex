defmodule NervesHub.DeviceLink.Dispatcher do
  @moduledoc """
  Decides where `NervesHub.DeviceLink` calls actually run.

  Nodes that hold the platform stack — the database, the contexts, the
  extensions — call it directly, in process. There is nothing to gain from a hop
  when everything needed is already here, so `Local` is the production path for
  them and is expected to stay that way.

  The seam exists for callers that are not those nodes: one that holds a device
  connection but has no database has to reach the platform somehow. Adding a
  second implementation is then a change here, not at every call site.

  Configure with:

      config :nerves_hub, NervesHub.DeviceLink.Dispatcher, SomeOtherImplementation

  """

  alias NervesHub.DeviceLink.Dispatcher.Local

  @doc """
  Run a `NervesHub.DeviceLink` function, wherever this node is configured to run it.
  """
  @callback call(function :: atom(), args :: [term()]) :: term()

  @spec call(atom(), [term()]) :: term()
  def call(function, args), do: impl().call(function, args)

  @doc "The configured implementation. Defaults to running in this process."
  @spec impl() :: module()
  def impl(), do: Application.get_env(:nerves_hub, __MODULE__, Local)
end

defmodule NervesHub.DeviceLink.Dispatcher.Local do
  @moduledoc """
  Runs `NervesHub.DeviceLink` calls in the calling process.

  A direct call — no serialisation, no network, nothing to fail separately. What
  every node carrying the platform stack uses.
  """

  @behaviour NervesHub.DeviceLink.Dispatcher

  @impl NervesHub.DeviceLink.Dispatcher
  def call(function, args), do: apply(NervesHub.DeviceLink, function, args)
end

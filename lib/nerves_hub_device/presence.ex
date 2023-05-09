defmodule NervesHubDevice.Presence do
  @moduledoc """
  Device Presence server

  Tracks online devices with `:gproc` as a local registry for metadata
  on the device.

  gproc selects are based on Erlang match specs, with the ETS flavor.

  Docs: https://www.erlang.org/doc/apps/erts/match_spec.html
  """

  alias NervesHub.Devices.Device

  @typedoc """
  Status of the current connection.
  Human readable string, should not be used
  pragmatically
  """
  @type status :: String.t()

  @type device_id_string :: String.t()

  @type device_presence :: %{
          connected_at: pos_integer(),
          console_available: boolean(),
          console_version: Version.build(),
          firmware_metadata: NervesHub.Firmwares.FirmwareMetadata.t(),
          last_communication: DateTime.t(),
          status: status(),
          update_available: boolean()
        }

  @type presence_list :: %{optional(device_id_string) => device_presence}

  @allowed_fields [
    :node,
    :product_id,
    :deployment_id,
    :connected_at,
    :console_available,
    :console_version,
    :firmware_metadata,
    :fwup_progress,
    :last_communication,
    :rebooting,
    :status,
    :update_available
  ]

  def __fields__(), do: @allowed_fields

  @doc """
  Track a device coming online

  The process calling track will now own the key / device for any updates
  and untracks going forward.
  """
  @spec track(Device.t(), map()) :: :ok
  def track(device, metadata, times \\ 0)

  def track(%Device{}, _metadata, times) when times >= 5 do
    raise "Failed to register a device after 5 attempts"
  end

  def track(%Device{} = device, metadata, times) do
    # insert the local node to make sure we can filter down later
    metadata = Map.put(metadata, :node, node())

    # Attempt to register the device and if it fails
    # terminate the other process since the new one
    # should be the winner. Then continue registration
    :gproc.reg({:n, :g, device.id}, metadata)

    # publish a device update message
    publish_change(device, metadata)
  rescue
    ArgumentError ->
      case whereis(device.id) do
        nil ->
          track(device, metadata, times + 1)

        pid ->
          GenServer.stop(pid)
          track(device, metadata, times + 1)
      end
  end

  @doc """
  Stop tracking a device

  Generally before it goes offline. This is helps gproc stay fast,
  instead of letting it clear itself out via process traps.
  """
  @spec untrack(Device.t()) :: :ok
  def untrack(%Device{} = device) do
    # publish a device update message
    :gproc.unreg({:n, :g, device.id})
    publish_change(device, %{status: "offline"})
  end

  @doc """
  Update a key to include merged metadata
  """
  @spec update(Device.t(), map()) :: :ok
  def update(%Device{} = device, new_metadata, publish \\ []) do
    # publish a device update message
    current_metadata = find(device)
    metadata = Map.merge(current_metadata, new_metadata)
    :gproc.set_value({:n, :g, device.id}, metadata)
    publish_change(device, metadata, publish)
  end

  defp publish_change(device, payload, publish \\ []) do
    payload =
      payload
      |> metadata()
      |> Map.put(:device_id, device.id)

    if Keyword.get(publish, :internal, true) do
      Phoenix.PubSub.broadcast(
        NervesHub.PubSub,
        "device:#{device.id}:internal",
        %Phoenix.Socket.Broadcast{event: "connection_change", payload: payload}
      )
    end

    if Keyword.get(publish, :product, true) do
      Phoenix.PubSub.broadcast(
        NervesHub.PubSub,
        "product:#{device.product_id}:devices",
        %Phoenix.Socket.Broadcast{event: "connection_change", payload: payload}
      )
    end
  end

  @doc """
  Find a device and return its metadata
  """
  @spec find(Device.t(), map()) :: map()
  def find(%Device{} = device, default_metadata \\ nil) do
    # match the key and return it's metadata (gproc value
    # {key, pid, value} where key is {type, scope, user key}
    case :gproc.select({:global, :names}, [
           {{{:_, :_, device.id}, :_, :_}, [], [{:element, 3, :"$_"}]}
         ]) do
      [metadata] ->
        metadata(metadata)

      [] ->
        default_metadata
    end
  end

  def local_deployment_device_pids(deployment) do
    :gproc.select({:global, :names}, [
      {{{:_, :_, :_}, :_, %{node: node(), deployment_id: deployment.id}}, [],
       [{:element, 2, :"$_"}]}
    ])
  end

  defp metadata(metadata) do
    case Map.take(metadata, @allowed_fields) do
      %{status: _status} = e ->
        e

      %{update_available: true} = e ->
        Map.put(e, :status, "update pending")

      %{rebooting: true} = e ->
        Map.put(e, :status, "rebooting")

      %{fwup_progress: _progress} = e ->
        Map.put(e, :status, "updating")

      e ->
        Map.put(e, :status, "online")
    end
  end

  @doc """
  Count the number of devices based on a metadata filter
  """
  @spec count(map()) :: integer()
  def count(metadata) do
    # count based on the metadata
    # first tuple is {key, pid, user value}
    # and thing returning `true` aka what's matched is counted
    :gproc.select_count({:g, :n}, [{{:_, :_, metadata}, [], [true]}])
  end

  @doc """
  Devices connected status

  If the device is found, the known status is returned, otherwise it's offline
  """
  @spec device_status(Device.t()) :: status()
  def device_status(%Device{} = device) do
    case find(device) do
      nil ->
        :offline

      metadata ->
        metadata.status
    end
  end

  @doc """
  Devices console status
  """
  @spec console_available(Device.t()) :: status()
  def console_available(%Device{} = device) do
    case find(device) do
      nil ->
        false

      metadata ->
        metadata.console_available
    end
  end

  @doc """
  Await for the device to be registered

  This returns the pid after it's registered
  """
  @spec await(Device.t()) :: pid()
  def await(%Device{} = device) do
    :gproc.await({:n, :g, device.id})
  end

  # developer helper function to find the pid of a device
  @doc false
  def whereis(key) do
    # match the key and return it's PID
    case :gproc.select({:global, :names}, [{{{:_, :_, key}, :_, :_}, [], [{:element, 2, :"$_"}]}]) do
      [pid] ->
        pid

      [] ->
        nil
    end
  end
end

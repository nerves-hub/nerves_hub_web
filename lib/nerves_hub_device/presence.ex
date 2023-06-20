defmodule NervesHubDevice.PresenceException do
  defexception [:message]

  @impl true
  def exception(message) do
    %__MODULE__{
      message: message
    }
  end
end

defmodule NervesHubDevice.Presence do
  @moduledoc """
  Device Presence server

  Tracks online devices with `:gproc` as a local registry for metadata
  on the device.

  gproc selects are based on Erlang match specs, with the ETS flavor.

  Docs: https://www.erlang.org/doc/apps/erts/match_spec.html
  """

  alias NervesHub.Devices.Device
  alias NervesHubDevice.PresenceException

  @typedoc """
  Status of the current connection.
  Human readable string, should not be used
  pragmatically
  """
  @type status :: String.t()

  @type device_id_string :: String.t()

  @type device_presence :: %{
          status: status()
        }

  @type presence_list :: %{optional(device_id_string) => device_presence}

  @allowed_fields [
    :status
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
    # Attempt to register the device and if it fails
    # terminate the other process since the new one
    # should be the winner. Then continue registration
    try do
      :gproc.reg({:n, :g, device.id}, metadata)
    catch
      :exit, value ->
        raise PresenceException, value
    end

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
    try do
      # publish a device update message
      :gproc.unreg({:n, :g, device.id})
    catch
      :exit, value ->
        raise PresenceException, value
    end

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

    try do
      :gproc.set_value({:n, :g, device.id}, metadata)
    catch
      :exit, value ->
        raise PresenceException, value
    end

    publish_change(device, metadata, publish)
  end

  defp publish_change(device, payload, publish \\ []) do
    payload = Map.put(payload, :device_id, device.id)

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
        metadata

      [] ->
        default_metadata
    end
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
  Await for the device to be registered

  This returns the pid after it's registered
  """
  @spec await(Device.t()) :: pid()
  def await(%Device{} = device) do
    try do
      :gproc.await({:n, :g, device.id})
    catch
      :exit, value ->
        raise PresenceException, value
    end
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

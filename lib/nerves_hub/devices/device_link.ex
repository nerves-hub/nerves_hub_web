defmodule NervesHub.Devices.DeviceLink do
  @moduledoc """
  GenServer to track a connected device

  Contains logic for a device separate from the transport layer,
  e.g. websockets.
  """

  # TODO any presence updates through a call should delay the message
  # for ~2 seconds and try again, using the call ref to reply.

  use GenServer

  alias NervesHubDevice.Presence
  alias Phoenix.Socket.Broadcast

  require Logger

  defmodule State do
    defstruct [:deployment_channel, :device, :transport_pid, :transport_ref]
  end

  def start_link(device) do
    GenServer.start_link(__MODULE__, device, name: name(device))
  end

  def name(device_id) when is_integer(device_id) do
    {:via, Registry, {NervesHub.Devices, {:link, device_id}}}
  end

  def name(device), do: name(device.id)

  def connect(pid, transport_pid) do
    GenServer.call(pid, {:connect, transport_pid})
  end

  def update_device(pid, device) do
    GenServer.call(pid, {:update_device, device})
  end

  def update_status(pid, status) do
    GenServer.call(pid, {:update_status, status})
  end

  def fwup_progress(pid, progress) do
    GenServer.call(pid, {:fwup_progress, progress})
  end

  def init(device) do
    {:ok, %State{device: device}, {:continue, :boot}}
  end

  def handle_continue(:boot, state) do
    subscribe("device:#{state.device.id}")

    state =
      if state.device.deployment_id do
        subscribe("deployment:#{state.device.deployment_id}")
        %{state | deployment_channel: "deployment:#{state.device.deployment_id}"}
      else
        subscribe("deployment:none")
        %{state | deployment_channel: "deployment:none"}
      end

    {:noreply, state}
  end

  # tracked after the device connects, so transport_pid should be present
  def handle_continue(:track, state) do
    Presence.track(state.device, %{})

    {:noreply, state}
  rescue
    PresenceException ->
      if state.transport_pid do
        send(state.transport_pid, :shutdown)
      end

      {:stop, :shutdown, state}
  end

  def handle_call({:update_device, device}, _from, state) do
    unsubscribe(state.deployment_channel)

    state = %{state | device: device}

    state =
      if device.deployment_id do
        subscribe("deployment:#{state.device.deployment_id}")
        %{state | deployment_channel: "deployment:#{state.device.deployment_id}"}
      else
        subscribe("deployment:none")
        %{state | deployment_channel: "deployment:none"}
      end

    {:reply, :ok, state}
  end

  def handle_call({:connect, transport_pid}, _from, state) do
    ref = Process.monitor(transport_pid)
    state = %{state | transport_pid: transport_pid, transport_ref: ref}
    {:reply, :ok, state, {:continue, :track}}
  end

  def handle_call({:update_status, status}, from, state) do
    Presence.update(state.device, %{status: status})

    {:reply, :ok, state}
  rescue
    PresenceException ->
      GenServer.reply(from, :shutdown)
      {:stop, :shutdown, state}
  end

  def handle_call({:fwup_progress, progress}, from, state) do
    # No need to update the product channel which will spam anyone listening on
    # the listing of devices.
    Presence.update(state.device, %{status: progress}, product: false)

    {:reply, :ok, state}
  rescue
    PresenceException ->
      GenServer.reply(from, :shutdown)
      {:stop, :shutdown, state}
  end

  def handle_info({:console, console_version}, state) do
    Presence.update(state.device, %{console_version: console_version})

    # now that the console is connected, push down the device's elixir, line by line
    device = state.device
    deployment = device.deployment

    if deployment && deployment.connecting_code do
      device.deployment.connecting_code
      |> String.graphemes()
      |> Enum.map(fn character ->
        broadcast("console:#{device.id}", "dn", %{
          "data" => character
        })
      end)

      broadcast("console:#{device.id}", "dn", %{"data" => "\r"})
    end

    if device.connecting_code do
      device.connecting_code
      |> String.graphemes()
      |> Enum.map(fn character ->
        broadcast("console:#{device.id}", "dn", %{
          "data" => character
        })
      end)

      broadcast("console:#{device.id}", "dn", %{"data" => "\r"})
    end

    {:noreply, state}
  rescue
    PresenceException ->
      if state.transport_pid do
        send(state.transport_pid, :shutdown)
      end

      {:stop, :shutdown, state}
  end

  def handle_info({:DOWN, transport_ref, :process, _pid, _reason}, state) do
    state =
      if transport_ref == state.transport_ref do
        %{state | transport_ref: nil}
      else
        state
      end

    Process.send_after(self(), :timeout_device, 3_000)

    {:noreply, state}
  end

  def handle_info(:timeout_device, state) do
    if is_nil(state.transport_ref) do
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  # Forward broadcasts to the channel for now
  def handle_info(%Broadcast{} = broadcast, state) do
    if state.transport_pid do
      send(state.transport_pid, broadcast)
    end

    {:noreply, state}
  end

  defp subscribe(topic) do
    Phoenix.PubSub.subscribe(NervesHub.PubSub, topic)
  end

  defp unsubscribe(topic) do
    Phoenix.PubSub.unsubscribe(NervesHub.PubSub, topic)
  end

  defp broadcast(topic, event, payload) do
    Phoenix.PubSub.broadcast(NervesHub.PubSub, topic, %Phoenix.Socket.Broadcast{
      event: event,
      payload: payload
    })
  end
end

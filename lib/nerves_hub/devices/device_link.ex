defmodule NervesHub.Devices.DeviceLink do
  @moduledoc """
  GenServer to track a connected device

  Contains logic for a device separate from the transport layer,
  e.g. websockets.
  """

  use GenServer

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
    {:reply, :ok, state}
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
end

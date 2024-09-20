defmodule NervesHubWeb.DeviceMonitor do
  use GenServer

  def monitor(pid, device, connection_ref) do
    GenServer.cast(__MODULE__, {:monitor, pid, [device, connection_ref]})
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    {:ok, %{devices: Map.new()}}
  end

  def handle_cast({:monitor, pid, args}, state) do
    ref = Process.monitor(pid)
    {:noreply, put_device(state, ref, args)}
  end

  def handle_info({:DOWN, ref, :process, _, _reason}, state) do
    case Map.fetch(state.devices, ref) do
      :error ->
        {:noreply, state}

      {:ok, args} ->
        apply(NervesHubWeb.DeviceChannel, :disconnected, args)
        {:noreply, drop_device(state, ref)}
    end
  end

  defp drop_device(state, pid) do
    %{state | devices: Map.delete(state.devices, pid)}
  end

  defp put_device(state, pid, info) do
    %{state | devices: Map.put(state.devices, pid, info)}
  end
end

defmodule NervesHubWeb.DeviceMonitor.Mock do
  def monitor(_, _, _), do: :ok
end

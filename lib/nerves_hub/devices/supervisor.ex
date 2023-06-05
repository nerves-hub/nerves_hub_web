defmodule NervesHub.Devices.Supervisor do
  use DynamicSupervisor

  alias NervesHub.Devices.DeviceLink

  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def start_device(device) do
    case GenServer.whereis(DeviceLink.name(device)) do
      nil ->
        DynamicSupervisor.start_child(__MODULE__, {DeviceLink, device})

      pid when is_pid(pid) ->
        {:ok, pid}
    end
  end

  @impl true
  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end

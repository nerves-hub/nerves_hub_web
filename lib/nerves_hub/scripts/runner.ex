defmodule NervesHub.Scripts.Runner do
  use GenServer

  alias NervesHubWeb.Endpoint

  defmodule State do
    defstruct [:buffer, :from, :receive_channel, :send_channel]
  end

  def send(device, command) do
    {:ok, pid} = start_link(device)
    GenServer.call(pid, {:send, command.text}, 10_000)
  end

  def start_link(device) do
    GenServer.start_link(__MODULE__, device.id)
  end

  def init(device_id) do
    state = %State{
      buffer: <<>>,
      from: nil,
      receive_channel: "user:console:#{device_id}",
      send_channel: "device:console:#{device_id}"
    }

    {:ok, state}
  end

  def handle_call({:send, text}, from, state) do
    text = ~s/#{text}\n# [NERVESHUB:END]/

    text
    |> String.graphemes()
    |> Enum.map(fn character ->
      Endpoint.broadcast_from!(self(), state.send_channel, "dn", %{"data" => character})
    end)

    Endpoint.subscribe(state.receive_channel)

    Endpoint.broadcast_from!(self(), state.send_channel, "dn", %{"data" => "\r"})

    {:noreply, %{state | from: from}}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "up", payload: %{"data" => text}}, state) do
    state = %{state | buffer: state.buffer <> text}

    if String.contains?(state.buffer, "[NERVESHUB:END]") do
      buffer =
        state.buffer
        |> String.split("\n")
        |> Enum.slice(0..-2//1)
        |> Enum.join("\n")

      GenServer.reply(state.from, buffer)

      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(_, state), do: {:noreply, state}
end

defmodule NervesHub.Scripts.Runner do
  @moduledoc """
  The runner will send the text the device channel in an attempt to
  use NervesHubLink on the device to evaluate the script directly.

  If the device has not been updated then the console channel will be
  used as a back up for catpuring output.

  Runner - {:send, text} -> DeviceChannel

  DeviceChannel - {:output, text} -> Runner
  DeviceChannel - {:error, :incompatible_version} -> Runner
  """

  use GenServer

  alias NervesHubWeb.Endpoint

  defmodule State do
    defstruct [:buffer, :device_channel, :from, :receive_channel, :send_channel, :text]
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
      device_channel: "device:#{device_id}",
      receive_channel: "user:console:#{device_id}",
      send_channel: "device:console:#{device_id}"
    }

    {:ok, state}
  end

  def handle_call({:send, text}, from, state) do
    Phoenix.PubSub.broadcast_from!(
      NervesHub.PubSub,
      self(),
      state.device_channel,
      {:run_script, self(), text}
    )

    {:noreply, %{state | from: from, text: text}}
  end

  def handle_info({:output, response}, state) do
    GenServer.reply(state.from, response)
    {:stop, :normal, state}
  end

  def handle_info({:error, :incompatible_version}, state) do
    text = ~s/#{state.text}\n# [NERVESHUB:END]/

    text
    |> String.graphemes()
    |> Enum.map(fn character ->
      Endpoint.broadcast_from!(self(), state.send_channel, "dn", %{"data" => character})
    end)

    Endpoint.subscribe(state.receive_channel)

    Endpoint.broadcast_from!(self(), state.send_channel, "dn", %{"data" => "\r"})

    {:noreply, state}
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

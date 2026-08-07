defmodule NervesHub.Scripts.Runner do
  @moduledoc """
  The runner will send the text the device channel in an attempt to
  use NervesHubLink on the device to evaluate the script directly.

  If the device has not been updated then the console channel will be
  used as a back up for capturing output.

  Runner - {:send, text} -> DeviceChannel

  DeviceChannel - {:output, text} -> Runner
  DeviceChannel - {:error, :incompatible_version} -> Runner
  """

  use GenServer

  alias NervesHub.Consoles.PubSub
  alias Phoenix.Socket.Broadcast

  defmodule State do
    defstruct [:buffer, :device_channel, :device_id, :from, :text]
  end

  def send(device, command, timeout \\ to_timeout(second: 30)) do
    {:ok, pid} = start_link(device)
    {:ok, GenServer.call(pid, {:send, command.text}, timeout)}
  catch
    :exit, _ -> {:error, "device did not respond in #{timeout} milliseconds"}
  end

  def start_link(device) do
    GenServer.start_link(__MODULE__, device.id)
  end

  def init(device_id) do
    state = %State{
      buffer: <<>>,
      from: nil,
      device_channel: "device:#{device_id}",
      device_id: device_id
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

    PubSub.broadcast_to_console(state.device_id, "dn", %{"data" => text})

    _ = PubSub.subscribe_user_console(state.device_id)

    PubSub.broadcast_to_console(state.device_id, "dn", %{"data" => "\r"})

    {:noreply, state}
  end

  def handle_info(%Broadcast{event: "up", payload: %{"data" => text}}, state) do
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

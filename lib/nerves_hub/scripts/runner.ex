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

  alias NervesHubWeb.Endpoint
  alias Phoenix.Socket.Broadcast

  @default_timeout to_timeout(second: 30)

  # The runner outlives the caller's deadline by this much, so a caller that is
  # still waiting always ends the call on its own `GenServer.call` timeout. The
  # deadline below is a backstop for the runner itself, not the usual path.
  @deadline_grace to_timeout(second: 1)

  defmodule State do
    defstruct [:buffer, :device_channel, :from, :receive_channel, :send_channel, :text, :timeout]
  end

  def send(device, command, timeout \\ @default_timeout) do
    {:ok, pid} = start_link(device, timeout)
    {:ok, GenServer.call(pid, {:send, command.text}, timeout)}
  catch
    :exit, _ -> {:error, "device did not respond in #{timeout} milliseconds"}
  end

  def start_link(device, timeout \\ @default_timeout) do
    GenServer.start_link(__MODULE__, {device.id, timeout})
  end

  def init({device_id, timeout}) do
    state = %State{
      buffer: <<>>,
      from: nil,
      timeout: timeout,
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

    # Nothing is guaranteed to answer: the device may be offline, so the
    # broadcast reaches nobody, or it may be too old to run scripts, in which
    # case we fall back to scraping the console for output that never arrives.
    # `send/3` catches its own call timeout, so without this the runner was left
    # running for the life of the node -- holding a console subscription and
    # appending every line the device printed to `buffer`.
    _ = Process.send_after(self(), :deadline, state.timeout + @deadline_grace)

    {:noreply, %{state | from: from, text: text}}
  end

  def handle_info({:output, response}, state) do
    GenServer.reply(state.from, response)
    {:stop, :normal, state}
  end

  def handle_info({:error, :incompatible_version}, state) do
    text = ~s/#{state.text}\n# [NERVESHUB:END]/

    Endpoint.broadcast_from!(self(), state.send_channel, "dn", %{"data" => text})

    _ = Endpoint.subscribe(state.receive_channel)

    Endpoint.broadcast_from!(self(), state.send_channel, "dn", %{"data" => "\r"})

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

  # The caller has already given up by now (see `@deadline_grace`), so there is
  # nobody left to reply to.
  def handle_info(:deadline, state), do: {:stop, :normal, state}

  def handle_info(_, state), do: {:noreply, state}
end

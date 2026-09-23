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

  @default_timeout to_timeout(second: 30)

  # The runner outlives the caller's deadline by this much, so a caller that is
  # still waiting always ends the call on its own `GenServer.call` timeout. The
  # deadline below is a backstop for the runner itself, not the usual path.
  @deadline_grace to_timeout(second: 1)

  defmodule State do
    defstruct [:buffer, :console_fallback?, :device_channel, :device_id, :from, :text, :timeout]
  end

  @doc """
  Run `command`'s text on `device` and wait for its output.

  ## Options

    * `:timeout` — how long the device has to answer. Also what the connection
      holds its reference for, so the whole budget is honoured end to end.
    * `:console_fallback?` — whether a device too old to run scripts should have
      its console scraped for the output instead. Defaults to `true`, which is
      what the single-device callers have always done. Bulk callers pass `false`:
      the fallback takes over a device's console for the length of the script,
      and doing that to hundreds of devices at once is not something to do
      quietly on their behalf.
  """
  @spec send(map(), map(), timeout() | keyword()) ::
          {:ok, String.t()} | {:error, String.t() | :unsupported}
  def send(device, command, opts \\ [])

  # Retains the original `send(device, command, timeout)` signature.
  def send(device, command, timeout) when is_integer(timeout) do
    send(device, command, timeout: timeout)
  end

  def send(device, command, opts) when is_list(opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    {:ok, pid} = start_link(device, opts)

    # The output paths reply with a bare binary; only the no-fallback
    # incompatible-version path replies with an error tuple of its own.
    case GenServer.call(pid, {:send, command.text}, timeout) do
      {:error, reason} -> {:error, reason}
      output -> {:ok, output}
    end
  catch
    :exit, _ ->
      {:error, "device did not respond in #{Keyword.get(opts, :timeout, @default_timeout)} milliseconds"}
  end

  def start_link(device, opts \\ [])

  def start_link(device, timeout) when is_integer(timeout) do
    start_link(device, timeout: timeout)
  end

  def start_link(device, opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, {device.id, opts})
  end

  def init({device_id, opts}) do
    state = %State{
      buffer: <<>>,
      from: nil,
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      console_fallback?: Keyword.get(opts, :console_fallback?, true),
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
      {:run_script, self(), text, state.timeout}
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

  # A device too old to run scripts. Callers that asked for the console fallback
  # get the script typed into the console instead; the rest are told plainly, so
  # they can record the outcome rather than wait out the deadline for output that
  # was never coming.
  def handle_info({:error, :incompatible_version}, %State{console_fallback?: false} = state) do
    GenServer.reply(state.from, {:error, :unsupported})
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

  # The caller has already given up by now (see `@deadline_grace`), so there is
  # nobody left to reply to.
  def handle_info(:deadline, state), do: {:stop, :normal, state}

  def handle_info(_, state), do: {:noreply, state}
end

defmodule NervesHub.Extensions.LocalShell do
  @behaviour NervesHub.Extensions

  alias NervesHub.Extensions.State
  alias Phoenix.Channel.Server, as: ChannelServer

  require Logger

  @impl NervesHub.Extensions
  def description() do
    """
    Connect to the devices local shell.
    """
  end

  @impl NervesHub.Extensions
  def enabled?() do
    true
  end

  @impl NervesHub.Extensions
  def attach(state) do
    state =
      state
      |> State.assign(:current_line, "")
      |> State.assign(:buffer, CircularBuffer.new(1024))

    {state, [{:push, "local_shell:request_shell", %{}}]}
  end

  @impl NervesHub.Extensions
  def detach(state) do
    state =
      state
      |> State.assign(:current_line, nil)
      |> State.assign(:buffer, nil)

    {state, []}
  end

  @impl NervesHub.Extensions
  def handle_in("shell_output", %{"data" => data}, state) do
    current_line = State.get(state, :current_line) <> data

    [current_line | lines] = Enum.reverse(String.split(current_line, "\n"))

    buffer =
      Enum.reduce(Enum.reverse(lines), State.get(state, :buffer), fn line, buffer ->
        CircularBuffer.insert(buffer, line <> "\n")
      end)

    state =
      state
      |> State.assign(:current_line, current_line)
      |> State.assign(:buffer, buffer)

    topic = "user:local_shell:#{state.device_info.device_id}"
    :ok = ChannelServer.broadcast!(NervesHub.PubSub, topic, "output", %{data: data})

    {state, []}
  end

  def handle_in(event, params, state) do
    Logger.warning(
      "[Extensions.LocalShell] unknown message received for device: #{inspect(state.device_info.device_id)} / #{inspect(event)} / #{inspect(params)}"
    )

    {state, []}
  end

  def handle_info({:connect, pid}, state) do
    lines = Enum.join(State.get(state, :buffer)) <> State.get(state, :current_line)

    send(pid, {:cache, lines})

    {state, []}
  end

  def handle_info({:active?, pid}, state) do
    send(pid, :active)

    {state, []}
  end

  @impl NervesHub.Extensions
  def handle_info(_msg, state) do
    {state, []}
  end
end

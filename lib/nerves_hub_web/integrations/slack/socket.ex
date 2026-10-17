defmodule NervesHubWeb.Integrations.Slack.Socket do
  @moduledoc """
  A Socket Mode connection to Slack: how an instance Slack cannot reach, such
  as one behind a VPN, still hears its events, button clicks and slash
  commands.

  Instead of Slack sending requests to `/integrations/slack/`, the instance
  asks Slack for a WebSocket with the app-level token
  (`NervesHub.Integrations.Slack.Client.open_socket/1`) and Slack sends each
  of them down it, wrapped in an envelope. Each envelope is acknowledged, and
  handled as the request would have been:

    * an event, by `NervesHubWeb.Integrations.Slack.EventCallbacks`
    * a button click, by `NervesHubWeb.Integrations.Slack.Actions.handle_interaction/1`
    * a slash command, by `NervesHubWeb.Integrations.Slack.Commands.handle/1`, whose
      answer goes back with the acknowledgement, as an HTTP response's body
      would

  Nothing is signed: the socket was opened with the app's token, so whatever
  comes down it is from Slack. Slack sends an envelope again when it is not
  acknowledged, and clicks and commands are acted on once by their
  `trigger_id` either way.

  Each web node runs two of these (`NervesHub.Application`). Slack gives each envelope to one open
  connection, and replaces every connection every few hours, so a second one
  carries on while the first reconnects. Slack allows ten at once.

  A connection that fails, or that Slack closes, is opened again, at once
  when Slack asked for it and after a growing pause otherwise.
  """
  use GenServer

  alias NervesHub.Integrations.Slack
  alias NervesHub.Integrations.Slack.Client
  alias NervesHubWeb.Integrations.Slack.Actions
  alias NervesHubWeb.Integrations.Slack.Commands
  alias NervesHubWeb.Integrations.Slack.EventCallbacks

  require Logger

  @connections 2

  @connect_timeout to_timeout(second: 10)
  @max_backoff to_timeout(minute: 1)

  @doc """
  The child specs for a node's connections, or none when the instance is not
  using Socket Mode.
  """
  @spec child_specs() :: [Supervisor.child_spec()]
  def child_specs() do
    if Slack.socket_mode?() do
      for n <- 1..@connections, do: Supervisor.child_spec({__MODULE__, []}, id: {__MODULE__, n})
    else
      []
    end
  end

  @doc """
  Starts a connection. `opts`:

    * `:app_token` – the app-level token, which defaults to the instance's
      (`SLACK_APP_TOKEN`)
    * `:notify` – a pid told `{:slack_socket, :connected}` each time Slack
      says hello, for tests
  """
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl GenServer
  def init(opts) do
    state = %{
      app_token: Keyword.get_lazy(opts, :app_token, fn -> Slack.config(:app_token) end),
      notify: opts[:notify],
      conn: nil,
      ref: nil,
      websocket: nil,
      upgrade_status: nil,
      upgrade_headers: nil,
      early_data: [],
      backoff: 0
    }

    {:ok, state, {:continue, :connect}}
  end

  @impl GenServer
  def handle_continue(:connect, state), do: {:noreply, connect(state)}

  @impl GenServer
  def handle_info(:connect, state), do: {:noreply, connect(state)}

  # A slash command's answer, from the task that worked it out. Dropped when
  # the connection it came in on has gone: the envelope was not acknowledged
  # on it, so Slack sends it again.
  def handle_info({:ack, ref, envelope_id, payload}, %{ref: ref} = state) do
    {:noreply, ack(state, envelope_id, payload)}
  end

  def handle_info({:ack, _ref, _envelope_id, _payload}, state), do: {:noreply, state}

  def handle_info(message, %{conn: conn} = state) when not is_nil(conn) do
    case Mint.WebSocket.stream(conn, message) do
      {:ok, conn, responses} ->
        {:noreply, Enum.reduce(responses, %{state | conn: conn}, &response/2)}

      {:error, conn, reason, _responses} ->
        {:noreply, reconnect(%{state | conn: conn}, "the connection failed: #{inspect(reason)}")}

      :unknown ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  ## Connecting

  defp connect(%{app_token: token} = state) when token in [nil, ""], do: state

  defp connect(state) do
    with {:ok, url} <- Client.open_socket(state.app_token),
         {:ok, conn, ref} <- open(URI.parse(url)) do
      %{state | conn: conn, ref: ref, websocket: nil, upgrade_status: nil, upgrade_headers: nil, early_data: []}
    else
      {:error, reason} -> reconnect(state, "Slack did not open a connection: #{inspect(reason)}")
      {:error, conn, reason} -> reconnect(%{state | conn: conn}, "the connection failed: #{inspect(reason)}")
    end
  end

  defp open(%URI{scheme: scheme, host: host, port: port} = uri) do
    {http, ws} = if scheme == "ws", do: {:http, :ws}, else: {:https, :wss}
    path = if uri.query, do: "#{uri.path}?#{uri.query}", else: uri.path || "/"

    with {:ok, conn} <-
           Mint.HTTP.connect(http, host, port, protocols: [:http1], transport_opts: [timeout: @connect_timeout]) do
      Mint.WebSocket.upgrade(ws, conn, path, [])
    end
  end

  # Slack asked for it, so straight away; otherwise after a pause that grows
  # with each failure in a row, so a Slack that is down is not hammered.
  defp reconnect(state, reason, delay \\ nil) do
    _ = if state.conn, do: Mint.HTTP.close(state.conn)

    delay = delay || state.backoff
    if delay > 0, do: Logger.warning("Slack Socket Mode: #{reason}; reconnecting in #{div(delay, 1000)}s")

    _ = Process.send_after(self(), :connect, delay)

    %{
      state
      | conn: nil,
        ref: nil,
        websocket: nil,
        upgrade_status: nil,
        upgrade_headers: nil,
        early_data: [],
        backoff: next_backoff(state.backoff)
    }
  end

  defp next_backoff(0), do: 1_000
  defp next_backoff(backoff), do: min(backoff * 2, @max_backoff)

  ## The upgrade, then frames

  defp response({:status, ref, status}, %{ref: ref} = state), do: %{state | upgrade_status: status}
  defp response({:headers, ref, headers}, %{ref: ref} = state), do: %{state | upgrade_headers: headers}

  # Frames sent straight after the upgrade, such as Slack's hello, can arrive in
  # the same packet as it. Mint hands those over as the 101's body, before
  # `:done`, so they are held until the WebSocket exists to decode them.
  defp response({:data, ref, data}, %{ref: ref, websocket: nil} = state) do
    %{state | early_data: [state.early_data | data]}
  end

  defp response({:done, ref}, %{ref: ref, websocket: nil, upgrade_status: status, upgrade_headers: headers} = state)
       when is_integer(status) and is_list(headers) do
    case Mint.WebSocket.new(state.conn, ref, status, headers) do
      {:ok, conn, websocket} ->
        early_data = IO.iodata_to_binary(state.early_data)
        state = %{state | conn: conn, websocket: websocket, early_data: []}
        if early_data == "", do: state, else: response({:data, ref, early_data}, state)

      {:error, conn, reason} ->
        reconnect(%{state | conn: conn}, "Slack refused the WebSocket: #{inspect(reason)}")
    end
  end

  defp response({:data, ref, data}, %{ref: ref, websocket: websocket} = state) when not is_nil(websocket) do
    case Mint.WebSocket.decode(websocket, data) do
      {:ok, websocket, frames} ->
        Enum.reduce(frames, %{state | websocket: websocket}, &frame/2)

      {:error, websocket, reason} ->
        reconnect(%{state | websocket: websocket}, "a frame could not be read: #{inspect(reason)}")
    end
  end

  defp response(_response, state), do: state

  defp frame(_frame, %{conn: nil} = state), do: state
  defp frame({:text, text}, state), do: text |> Jason.decode() |> message(state)
  defp frame({:ping, data}, state), do: send_frame(state, {:pong, data})
  defp frame({:close, _code, reason}, state), do: reconnect(state, "Slack closed the connection: #{reason}")
  defp frame(_frame, state), do: state

  ## Slack's messages

  defp message({:ok, %{"type" => "hello"}}, state) do
    if state.notify, do: send(state.notify, {:slack_socket, :connected})
    Logger.info("Slack Socket Mode: connected")
    %{state | backoff: 0}
  end

  # Sent before Slack closes a connection, to replace it or because Socket
  # Mode was turned off; either way the next one is opened now.
  defp message({:ok, %{"type" => "disconnect", "reason" => reason}}, state) do
    Logger.info("Slack Socket Mode: Slack is replacing the connection (#{reason})")
    reconnect(state, reason, 0)
  end

  defp message({:ok, %{"envelope_id" => envelope_id, "type" => type, "payload" => payload}}, state)
       when is_binary(envelope_id) and is_map(payload) do
    envelope(type, envelope_id, payload, state)
  end

  defp message(_unknown, state), do: state

  # Acknowledged at once, then handled off the connection's process.
  defp envelope("events_api", envelope_id, payload, state) do
    :ok = run(fn -> :ok = EventCallbacks.handle(payload) end)
    ack(state, envelope_id)
  end

  defp envelope("interactive", envelope_id, payload, state) do
    :ok = run(fn -> :ok = Actions.handle_interaction(payload) end)
    ack(state, envelope_id)
  end

  # The command's answer is the acknowledgement's payload, so the ack waits
  # for it, which `Commands.handle/1` keeps well inside Slack's three seconds.
  defp envelope("slash_commands", envelope_id, payload, state) do
    socket = self()
    ref = state.ref
    :ok = run(fn -> send(socket, {:ack, ref, envelope_id, Commands.handle(payload)}) end)
    state
  end

  defp envelope(_type, envelope_id, _payload, state), do: ack(state, envelope_id)

  defp run(fun) do
    {:ok, _pid} = Task.Supervisor.start_child(NervesHub.TaskSupervisor, fun)
    :ok
  end

  defp ack(state, envelope_id, payload \\ nil) do
    body = if payload, do: %{envelope_id: envelope_id, payload: payload}, else: %{envelope_id: envelope_id}
    send_frame(state, {:text, Jason.encode!(body)})
  end

  defp send_frame(%{websocket: nil} = state, _frame), do: state

  defp send_frame(state, frame) do
    case Mint.WebSocket.encode(state.websocket, frame) do
      {:ok, websocket, data} ->
        case Mint.WebSocket.stream_request_body(state.conn, state.ref, data) do
          {:ok, conn} -> %{state | conn: conn, websocket: websocket}
          {:error, conn, reason} -> reconnect(%{state | conn: conn}, "a frame could not be sent: #{inspect(reason)}")
        end

      {:error, websocket, reason} ->
        reconnect(%{state | websocket: websocket}, "a frame could not be encoded: #{inspect(reason)}")
    end
  end
end

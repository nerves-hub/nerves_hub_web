defmodule NervesHub.Analytics.Buffer do
  @moduledoc """
  Batches writes to `NervesHub.AnalyticsRepo` into a single `insert_all` per flush.

  ClickHouse builds a new part for every INSERT, so a row-at-a-time write pattern
  costs a part per event and a connection from the (small) analytics pool. Device
  connection events and log lines both arrive at fleet scale, so they go through
  here instead: rows accumulate in one process per table and are written as one
  batch when the batch fills up or the delay elapses, whichever comes first.

  A buffer is started per schema, and the flush itself runs in a task so the
  buffer keeps draining its mailbox while ClickHouse is slow. At most one flush
  is in flight at a time - rows that arrive during a flush are picked up by the
  next one, so a slow ClickHouse produces fewer, larger batches rather than a
  pile-up of concurrent inserts.

  Analytics data is sampled telemetry, not a system of record. If the buffer
  passes `:max_buffer_size` (ClickHouse being down or unreachable, say), the
  oldest half is dropped so the node stays up and recent rows still get through.
  Drops are logged and reported via
  `[:nerves_hub, :analytics, :buffer, :dropped]`.
  """

  use GenServer

  require Logger

  @default_max_batch_size 1_000
  @default_max_delay to_timeout(millisecond: 500)
  @default_max_buffer_size 50_000

  defmodule State do
    @moduledoc false

    defstruct [
      :fields,
      :flush_ref,
      :max_batch_size,
      :max_buffer_size,
      :max_delay,
      :name,
      :schema,
      :timer,
      count: 0,
      rows: []
    ]
  end

  @doc """
  Starts a buffer for a single analytics schema.

  ## Options

    * `:schema` - required, the Ecto schema whose rows this buffer batches.
    * `:name` - the registered name, defaults to the schema module.
    * `:max_batch_size` - flush once this many rows are buffered.
    * `:max_delay` - flush this long after the first row of a batch is buffered.
    * `:max_buffer_size` - drop the oldest rows beyond this many.
  """
  def start_link(opts) do
    schema = Keyword.fetch!(opts, :schema)
    name = Keyword.get(opts, :name, schema)

    GenServer.start_link(__MODULE__, Keyword.put(opts, :name, name), name: name)
  end

  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, Keyword.fetch!(opts, :schema)),
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @doc """
  Buffers a changeset for the next batch.

  The changeset is flattened to a row here, in the calling process, so the
  buffer only ever appends. Returns `:ok` without waiting for the write.
  """
  @spec insert(GenServer.name(), Ecto.Changeset.t()) :: :ok
  def insert(name, %Ecto.Changeset{} = changeset) do
    GenServer.cast(name, {:insert, changeset})
  end

  @doc """
  Writes everything currently buffered and waits for ClickHouse to accept it.

  Waits for an in-flight flush too, so on return every row buffered before the
  call is readable. Used on shutdown, and by tests that read back what they
  just wrote.
  """
  @spec flush(GenServer.name(), timeout()) :: :ok
  def flush(name, timeout \\ to_timeout(second: 15)) do
    GenServer.call(name, :flush, timeout)
  end

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)

    schema = Keyword.fetch!(opts, :schema)

    state = %State{
      schema: schema,
      fields: schema.__schema__(:fields),
      name: Keyword.fetch!(opts, :name),
      max_batch_size: Keyword.get(opts, :max_batch_size, @default_max_batch_size),
      max_delay: Keyword.get(opts, :max_delay, @default_max_delay),
      max_buffer_size: Keyword.get(opts, :max_buffer_size, @default_max_buffer_size)
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:insert, changeset}, state) do
    state
    |> buffer(to_row(changeset, state.fields))
    |> maybe_flush()
    |> noreply()
  end

  @impl GenServer
  def handle_call(:flush, _from, state) do
    # Inline rather than via the flush task: the caller is asking for the rows
    # to be readable by the time this returns, including any already in flight.
    state = await_flush(state)
    {rows, state} = take_rows(state)
    _ = write(rows, state)

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info(:flush, state) do
    %{state | timer: nil}
    |> flush_async()
    |> noreply()
  end

  # The in-flight flush finished. Anything buffered while it ran goes out now.
  def handle_info({ref, _result}, %State{flush_ref: ref} = state) do
    Process.demonitor(ref, [:flush])

    %{state | flush_ref: nil}
    |> flush_async()
    |> noreply()
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %State{flush_ref: ref} = state) do
    Logger.warning("Analytics buffer flush crashed",
      schema: inspect(state.schema),
      reason: inspect(reason)
    )

    %{state | flush_ref: nil}
    |> flush_async()
    |> noreply()
  end

  def handle_info(_message, state), do: noreply(state)

  @impl GenServer
  def terminate(_reason, state) do
    state = await_flush(state)
    {rows, state} = take_rows(state)
    _ = write(rows, state)

    :ok
  end

  # Rows are newest-first, so keeping the head keeps the most recent half. Halving
  # rather than dropping per-row keeps this amortised O(1) while overloaded.
  defp buffer(%State{count: count, max_buffer_size: max} = state, row) when count >= max do
    keep = div(max, 2)
    dropped = count - keep

    Logger.warning("Analytics buffer full, dropping oldest rows",
      schema: inspect(state.schema),
      buffered: count,
      dropped: dropped
    )

    :telemetry.execute([:nerves_hub, :analytics, :buffer, :dropped], %{count: dropped}, %{
      schema: state.schema
    })

    %{state | rows: [row | Enum.take(state.rows, keep)], count: keep + 1}
  end

  defp buffer(state, row) do
    %{state | rows: [row | state.rows], count: state.count + 1}
  end

  defp maybe_flush(%State{count: count, max_batch_size: max} = state) when count >= max do
    flush_async(state)
  end

  defp maybe_flush(state), do: start_timer(state)

  # A flush is already running - let it pick these rows up when it finishes.
  defp flush_async(%State{flush_ref: ref} = state) when is_reference(ref), do: state

  defp flush_async(%State{count: 0} = state), do: state

  defp flush_async(state) do
    {rows, state} = take_rows(state)

    task =
      Task.Supervisor.async_nolink(NervesHub.TaskSupervisor, fn -> write(rows, state) end)

    %{state | flush_ref: task.ref}
  end

  defp await_flush(%State{flush_ref: nil} = state), do: state

  defp await_flush(%State{flush_ref: ref} = state) do
    receive do
      {^ref, _result} ->
        Process.demonitor(ref, [:flush])
        %{state | flush_ref: nil}

      {:DOWN, ^ref, :process, _pid, _reason} ->
        %{state | flush_ref: nil}
    after
      to_timeout(second: 10) ->
        %{state | flush_ref: nil}
    end
  end

  defp write([], _state), do: :ok

  defp write(rows, state) do
    started_at = System.monotonic_time()

    _ = NervesHub.AnalyticsRepo.insert_all(state.schema, rows, settings: [async_insert: 1])

    :telemetry.execute(
      [:nerves_hub, :analytics, :buffer, :flush],
      %{count: length(rows), duration: System.monotonic_time() - started_at},
      %{schema: state.schema}
    )

    :ok
  rescue
    error ->
      Logger.error("Analytics buffer flush failed",
        schema: inspect(state.schema),
        count: length(rows),
        error: Exception.message(error)
      )

      _ =
        Sentry.capture_exception(error,
          stacktrace: __STACKTRACE__,
          extra: %{schema: inspect(state.schema), count: length(rows)},
          result: :none
        )

      :error
  end

  defp take_rows(state) do
    {Enum.reverse(state.rows), %{state | rows: [], count: 0, timer: cancel_timer(state.timer)}}
  end

  # Only the first row of a batch arms the timer, so an idle buffer holds none.
  defp start_timer(%State{timer: nil, count: count} = state) when count > 0 do
    %{state | timer: Process.send_after(self(), :flush, state.max_delay)}
  end

  defp start_timer(state), do: state

  defp cancel_timer(nil), do: nil

  defp cancel_timer(timer) do
    _ = Process.cancel_timer(timer)
    nil
  end

  # `insert_all` builds one statement for the batch, so every row must carry the
  # same keys. Going through the struct fills in schema defaults for whatever
  # the changeset left untouched.
  defp to_row(changeset, fields) do
    changeset
    |> Ecto.Changeset.apply_changes()
    |> Map.take(fields)
  end

  defp noreply(state), do: {:noreply, state}
end

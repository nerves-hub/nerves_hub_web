defmodule NervesHub.ErrorReports.GroupBuffer do
  @moduledoc """
  Coalesces error-group upserts into one statement per flush.

  A device in a crash loop reports the same bug hundreds of times a second, and
  every one of those reports targets the **same** `error_groups` row. Upserting
  per report puts every device node in the cluster into a lock queue on that one
  row, at exactly the moment the platform is busiest.

  So occurrences go straight to ClickHouse through `NervesHub.Analytics.Buffer`,
  and the group side comes through here: reports are merged in memory, keyed by
  `{product_id, fingerprint}`, and written as a single `insert_all` with an
  upsert when the batch fills up or the delay elapses. A crash loop becomes one
  statement per node per window rather than one per crash.

  The coalescing is also what makes the statement legal. Postgres refuses an
  `ON CONFLICT DO UPDATE` that would touch the same row twice in one command,
  so a batch that had not been merged first would fail outright.

  ## Reopening

  A group that was resolved and happens again goes back in the queue, and that
  decision is made in the conflict clause rather than by a second query — a
  reopen costs nothing that the upsert was not already paying.

  Muted groups are left alone. They keep counting and they do not reopen, which
  is the entire difference between muting something and resolving it.

  ## Losing a batch

  Unlike `NervesHub.Analytics.Buffer`, nothing here is dropped under pressure:
  the buffer is keyed by group, so its size is bounded by how many *distinct*
  errors a node has seen, not by how often they happen. A flood of new
  fingerprints flushes early instead of overflowing.

  A node that dies with a batch in hand loses those counts. The occurrences
  themselves are already on their way to ClickHouse, so what is lost is a number
  being slightly low, and that is the right trade against making a crash loop
  serialise on one row.
  """

  use GenServer

  import Ecto.Query

  alias NervesHub.ErrorReports.ErrorGroup
  alias NervesHub.Repo

  require Logger

  @default_max_batch_size 500
  @default_max_delay to_timeout(second: 1)

  defmodule State do
    @moduledoc false

    defstruct [:flush_ref, :max_batch_size, :max_delay, :name, :timer, groups: %{}]
  end

  @doc """
  Starts the buffer.

  ## Options

    * `:name` - the registered name, defaults to this module.
    * `:max_batch_size` - flush once this many distinct groups are buffered.
    * `:max_delay` - flush this long after the first group of a batch arrives.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)

    GenServer.start_link(__MODULE__, Keyword.put(opts, :name, name), name: name)
  end

  def child_spec(opts) do
    %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}
  end

  @doc """
  Merges one occurrence into the batch.

  `attrs` is a report that has been through `NervesHub.ErrorReports.Payload`,
  plus the `:product_id`, `:fingerprint` and `:fingerprint_version` the context
  resolved. Returns `:ok` without waiting for the write.
  """
  @spec record(GenServer.name(), map()) :: :ok
  def record(name \\ __MODULE__, attrs) do
    GenServer.cast(name, {:record, key(attrs), entry(attrs)})
  end

  @doc """
  Writes everything currently buffered and waits for Postgres to accept it.

  Waits for an in-flight flush too, so on return every group merged before the
  call is readable. Used on shutdown, and by tests that read back what they just
  recorded.
  """
  @spec flush(GenServer.name(), timeout()) :: :ok
  def flush(name \\ __MODULE__, timeout \\ to_timeout(second: 15)) do
    GenServer.call(name, :flush, timeout)
  end

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)

    {:ok,
     %State{
       name: Keyword.fetch!(opts, :name),
       max_batch_size: Keyword.get(opts, :max_batch_size, @default_max_batch_size),
       max_delay: Keyword.get(opts, :max_delay, @default_max_delay)
     }}
  end

  @impl GenServer
  def handle_cast({:record, key, entry}, state) do
    state
    |> merge(key, entry)
    |> maybe_flush()
    |> noreply()
  end

  @impl GenServer
  def handle_call(:flush, _from, state) do
    # Inline rather than through the flush task: the caller is asking for the
    # rows to be readable by the time this returns, including any in flight.
    state = await_flush(state)
    {groups, state} = take_groups(state)
    _ = write(groups)

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info(:flush, state) do
    %{state | timer: nil}
    |> flush_async()
    |> noreply()
  end

  def handle_info({ref, _result}, %State{flush_ref: ref} = state) do
    Process.demonitor(ref, [:flush])

    %{state | flush_ref: nil}
    |> flush_async()
    |> noreply()
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %State{flush_ref: ref} = state) do
    Logger.warning("Error group buffer flush crashed", reason: inspect(reason))

    %{state | flush_ref: nil}
    |> flush_async()
    |> noreply()
  end

  def handle_info(_message, state), do: noreply(state)

  @impl GenServer
  def terminate(_reason, state) do
    state = await_flush(state)
    {groups, _state} = take_groups(state)
    _ = write(groups)

    :ok
  end

  # -------------------------------------------------------------- coalescing

  defp key(attrs), do: {attrs.product_id, attrs.fingerprint}

  defp entry(attrs) do
    top_frame = List.first(attrs.frames) || %{module: nil, function: nil, file: nil, line: nil}

    %{
      product_id: attrs.product_id,
      fingerprint: attrs.fingerprint,
      fingerprint_version: attrs.fingerprint_version,
      kind: attrs.kind,
      source: attrs.source,
      reason: attrs.reason,
      top_frame_module: top_frame.module,
      top_frame_function: top_frame.function,
      top_frame_file: top_frame.file,
      top_frame_line: top_frame.line,
      occurrence_count: 1,
      first_seen_at: attrs.timestamp,
      last_seen_at: attrs.timestamp,
      first_seen_firmware_uuid: attrs.firmware_uuid,
      last_seen_firmware_uuid: attrs.firmware_uuid
    }
  end

  defp merge(state, key, entry) do
    %{state | groups: Map.update(state.groups, key, entry, &combine(&1, entry))}
  end

  # The newest occurrence in a batch supplies what the group shows, the oldest
  # supplies what it was first seen as. Reports can arrive out of order — a
  # device that buffered across a disconnect sends its backlog behind whatever
  # it is crashing on now — so neither end is assumed.
  defp combine(existing, incoming) do
    # Everything the group displays comes from the newest occurrence, so start
    # from that one and correct the two fields it cannot know on its own.
    newer =
      if DateTime.after?(incoming.last_seen_at, existing.last_seen_at) do
        incoming
      else
        existing
      end

    {first_seen_at, first_seen_firmware_uuid} =
      if DateTime.before?(incoming.first_seen_at, existing.first_seen_at) do
        {incoming.first_seen_at, incoming.first_seen_firmware_uuid}
      else
        {existing.first_seen_at, existing.first_seen_firmware_uuid}
      end

    %{
      newer
      | occurrence_count: existing.occurrence_count + incoming.occurrence_count,
        first_seen_at: first_seen_at,
        first_seen_firmware_uuid: first_seen_firmware_uuid
    }
  end

  # ------------------------------------------------------------------ writing

  defp write(groups) when map_size(groups) == 0, do: :ok

  defp write(groups) do
    # `timestamps()` on this table is `:naive_datetime`, the repo's default, and
    # `insert_all` validates types rather than casting them — a `DateTime` here
    # is rejected outright. The occurrence timestamps are separate and are
    # `:utc_datetime_usec`, which is why only these two are naive.
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    rows =
      for {_key, entry} <- groups do
        entry
        |> Map.put(:status, :unresolved)
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end

    {count, _returning} =
      Repo.insert_all(ErrorGroup, rows,
        on_conflict: on_conflict(),
        conflict_target: [:product_id, :fingerprint]
      )

    :telemetry.execute([:nerves_hub, :error_reports, :group_buffer, :flush], %{count: count}, %{})

    :ok
  rescue
    error ->
      Logger.error("Error group buffer flush failed",
        count: map_size(groups),
        error: Exception.message(error)
      )

      _ =
        Sentry.capture_exception(error,
          stacktrace: __STACKTRACE__,
          extra: %{count: map_size(groups)},
          result: :none
        )

      :error
  end

  # Every column that moves does so relative to what is already stored, because
  # two nodes can be flushing the same group at the same moment and neither has
  # read the row. `EXCLUDED` is the batch we are trying to insert.
  defp on_conflict() do
    from(g in ErrorGroup,
      update: [
        set: [
          occurrence_count: fragment("? + EXCLUDED.occurrence_count", g.occurrence_count),
          last_seen_at: fragment("GREATEST(?, EXCLUDED.last_seen_at)", g.last_seen_at),
          first_seen_at: fragment("LEAST(?, EXCLUDED.first_seen_at)", g.first_seen_at),
          # The companions of the two timestamps above follow whichever side
          # won, so a group never shows a firmware from one occurrence next to
          # a time from another.
          last_seen_firmware_uuid:
            fragment(
              "CASE WHEN EXCLUDED.last_seen_at >= ? THEN EXCLUDED.last_seen_firmware_uuid ELSE ? END",
              g.last_seen_at,
              g.last_seen_firmware_uuid
            ),
          first_seen_firmware_uuid:
            fragment(
              "CASE WHEN EXCLUDED.first_seen_at < ? THEN EXCLUDED.first_seen_firmware_uuid ELSE ? END",
              g.first_seen_at,
              g.first_seen_firmware_uuid
            ),
          reason:
            fragment(
              "CASE WHEN EXCLUDED.last_seen_at >= ? THEN EXCLUDED.reason ELSE ? END",
              g.last_seen_at,
              g.reason
            ),
          # Resolved and happening again goes back in the queue. Muted stays
          # muted — that is what muting is for.
          status: fragment("CASE WHEN ? = 'resolved' THEN 'unresolved' ELSE ? END", g.status, g.status),
          regressed_at:
            fragment(
              "CASE WHEN ? = 'resolved' THEN EXCLUDED.last_seen_at ELSE ? END",
              g.status,
              g.regressed_at
            ),
          updated_at: fragment("EXCLUDED.updated_at")
        ]
      ]
    )
  end

  # ----------------------------------------------------------------- flushing

  defp maybe_flush(%State{max_batch_size: max} = state) when map_size(state.groups) >= max do
    flush_async(state)
  end

  defp maybe_flush(state), do: start_timer(state)

  defp flush_async(%State{flush_ref: ref} = state) when is_reference(ref), do: state

  defp flush_async(%State{groups: groups} = state) when map_size(groups) == 0, do: state

  defp flush_async(state) do
    {groups, state} = take_groups(state)

    task = Task.Supervisor.async_nolink(NervesHub.TaskSupervisor, fn -> write(groups) end)

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
      to_timeout(second: 10) -> %{state | flush_ref: nil}
    end
  end

  defp take_groups(state) do
    {state.groups, %{state | groups: %{}, timer: cancel_timer(state.timer)}}
  end

  defp start_timer(%State{timer: nil, groups: groups} = state) when map_size(groups) > 0 do
    %{state | timer: Process.send_after(self(), :flush, state.max_delay)}
  end

  defp start_timer(state), do: state

  defp cancel_timer(nil), do: nil

  defp cancel_timer(timer) do
    _ = Process.cancel_timer(timer)
    nil
  end

  defp noreply(state), do: {:noreply, state}
end

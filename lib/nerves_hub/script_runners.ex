defmodule NervesHub.ScriptRunners do
  @moduledoc """
  Running one script across many of a product's devices, and what each of them
  said.

  A run is created with its whole target set resolved up front: every matching
  device gets a `ScriptRunnerDevice` row at `:pending`, and Oban works through
  them. `NervesHub.Workers.ScriptRunnerDispatch` paces each run, and
  `NervesHub.Workers.ScriptRunnerDevice` runs the script on one device.

  Because the queue is rows in Postgres rather than state in a process, a run
  survives the node that started it: another web node picks up what is left.

  There is deliberately no function here that updates a run's `text` — a run is a
  record of what ran. See `NervesHub.ScriptRunners.ScriptRunner`.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Ecto.Multi
  alias NervesHub.Accounts.Scope
  alias NervesHub.Accounts.User
  alias NervesHub.AuditLogs.ProductTemplates
  alias NervesHub.Devices.Device
  alias NervesHub.Filtering, as: CommonFiltering
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias NervesHub.ScriptRunners.PubSub
  alias NervesHub.ScriptRunners.ScriptRunner
  alias NervesHub.ScriptRunners.ScriptRunnerDevice
  alias NervesHub.ScriptRunners.ScriptRunnerDeviceFiltering
  alias NervesHub.Workers.ScriptRunnerDispatch

  # One statement per chunk, so a run targeting a whole fleet does not build a
  # single multi-megabyte insert.
  @insert_chunk_size 5_000

  # Matched against `oban_jobs.worker`, which stores the worker as a string.
  @device_worker "NervesHub.Workers.ScriptRunnerDevice"
  @dispatch_worker "NervesHub.Workers.ScriptRunnerDispatch"

  # A job in one of these states can still run its device. Anything else --
  # `completed`, `discarded`, `cancelled` -- never will, so the device's row is
  # free to be released. See `release_stale_devices/2`.
  @live_job_states ~w(available scheduled executing retryable)

  @doc """
  Create a run and queue its first pacing job.

  Resolves the filter to a device set and records a row per device, all in one
  transaction with the dispatch job that starts working through them. Returns the
  run, plus any identifiers the filter asked for that matched no device.
  """
  @spec create(Scope.t(), User.t(), map()) ::
          {:ok, ScriptRunner.t(), [String.t()]} | {:error, Changeset.t()} | {:error, :no_devices}
  def create(%Scope{product: %Product{} = product}, user, params) do
    create(product, user, params)
  end

  @spec create(Product.t(), User.t(), map()) ::
          {:ok, ScriptRunner.t(), [String.t()]} | {:error, Changeset.t()} | {:error, :no_devices}
  def create(%Product{} = product, user, params) do
    changeset = ScriptRunner.create_changeset(product, user, params)

    with {:ok, runner} <- Changeset.apply_action(changeset, :insert),
         {device_ids, unmatched} = resolve_targets(product, runner.filter_type, runner.filter),
         :ok <- ensure_targets(device_ids) do
      insert(changeset, product, user, device_ids, unmatched)
    end
  end

  defp ensure_targets([]), do: {:error, :no_devices}
  defp ensure_targets(_device_ids), do: :ok

  # The device rows and the job that works through them are inserted together: a
  # run whose devices were recorded but whose dispatch job was not would sit at
  # `:pending` with nothing coming for it.
  defp insert(changeset, product, user, device_ids, unmatched) do
    Multi.new()
    |> Multi.insert(:runner, Changeset.put_change(changeset, :device_count, length(device_ids)))
    |> Multi.run(:devices, fn repo, %{runner: runner} ->
      {:ok, insert_device_rows(repo, runner, device_ids)}
    end)
    |> Oban.insert(:dispatch, fn %{runner: runner} ->
      ScriptRunnerDispatch.new(%{script_runner_id: runner.id})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{runner: runner}} ->
        :ok = ProductTemplates.audit_script_runner_created(user, product, runner)

        {:ok, runner, unmatched}

      {:error, _step, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp insert_device_rows(repo, runner, device_ids) do
    # `timestamps()` on this table is `:naive_datetime`, the repo's default, and
    # `insert_all` validates types rather than casting them -- a `DateTime` here
    # is rejected outright. The status timestamps are `:utc_datetime_usec` and are
    # set later, through `update_all`.
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    device_ids
    |> Enum.chunk_every(@insert_chunk_size)
    |> Enum.reduce(0, fn chunk, count ->
      rows =
        Enum.map(chunk, fn device_id ->
          %{
            script_runner_id: runner.id,
            device_id: device_id,
            status: :pending,
            inserted_at: now,
            updated_at: now
          }
        end)

      {inserted, nil} = repo.insert_all(ScriptRunnerDevice, rows)

      count + inserted
    end)
  end

  @doc """
  The devices a filter selects, and the identifiers it named that matched none.

  Only the identifier filter can name something that does not exist, so the
  second element is always empty for the others.
  """
  @spec resolve_targets(Product.t(), ScriptRunner.filter_type(), map()) :: {[integer()], [String.t()]}
  def resolve_targets(%Product{} = product, :identifiers, filter) do
    # Already split by the changeset, so this is a plain list by the time a run
    # exists.
    identifiers = filter.identifiers

    found =
      product
      |> targetable_devices()
      |> where([d], d.identifier in ^identifiers)
      |> select([d], {d.id, d.identifier})
      |> Repo.all()

    {Enum.map(found, &elem(&1, 0)), identifiers -- Enum.map(found, &elem(&1, 1))}
  end

  def resolve_targets(%Product{} = product, :tags, filter) do
    device_ids =
      product
      |> targetable_devices()
      |> where_matching_tags(filter.tags, filter.tag_operator)
      |> select([d], d.id)
      |> Repo.all()

    {device_ids, []}
  end

  def resolve_targets(%Product{} = product, :deployment_groups, filter) do
    device_ids =
      product
      |> targetable_devices()
      |> where([d], d.deployment_id in ^filter.deployment_group_ids)
      |> select([d], d.id)
      |> Repo.all()

    {device_ids, []}
  end

  # A soft-deleted device is not a device anyone means to run a script on.
  defp targetable_devices(product) do
    Device
    |> where([d], d.product_id == ^product.id)
    |> where([d], is_nil(d.deleted_at))
  end

  # The same array operators deployment group conditions match on, rather than
  # the device filters' trigram ILIKE -- targeting has to mean the tag, not a
  # substring of one.
  #
  # Both operators are matched explicitly, with nothing to fall through to: the
  # changeset requires one to have been chosen, so anything else here is a run
  # that got past that, and quietly picking one would send a script to a fleet
  # nobody selected.
  #
  # "Allow any": the device carries at least one of the tags.
  defp where_matching_tags(query, tags, :or) do
    where(query, [d], fragment("?::text[] && tags::text[]", ^tags))
  end

  # "Require all": the device carries every one of them.
  defp where_matching_tags(query, tags, :and) do
    where(query, [d], fragment("?::text[] <@ tags::text[]", ^tags))
  end

  @doc """
  A product's runs, paginated and filtered for the listing page.

  Sorted newest first unless asked otherwise: a run has no name to order by, and
  the most recent one is nearly always what someone came to look at.
  """
  @spec filter(Scope.t() | Product.t(), map()) :: {[ScriptRunner.t()], Flop.Meta.t()}
  def filter(scope_or_product, opts \\ %{})

  def filter(%Scope{product: product}, opts), do: filter(product, opts)

  def filter(%Product{} = product, opts) do
    opts = Map.put_new(opts, :sort, {:desc, :inserted_at})

    ScriptRunner
    |> from()
    |> CommonFiltering.filter(product, opts)
  end

  @doc """
  A product's runs, newest first.
  """
  @spec all_by_product(Product.t()) :: [ScriptRunner.t()]
  def all_by_product(%Product{} = product) do
    ScriptRunner
    |> where([sr], sr.product_id == ^product.id)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Fetch a run within a product's scope.
  """
  @spec get_by_id!(Scope.t() | Product.t(), integer() | String.t()) :: ScriptRunner.t()
  def get_by_id!(%Scope{product: product}, id), do: get_by_id!(product, id)

  def get_by_id!(%Product{} = product, id) do
    ScriptRunner
    |> where([sr], sr.id == ^id and sr.product_id == ^product.id)
    |> Repo.one!()
  end

  @doc """
  What each of a run's devices did, ordered by device identifier.
  """
  @spec device_results(ScriptRunner.t()) :: [ScriptRunnerDevice.t()]
  def device_results(%ScriptRunner{id: id}) do
    ScriptRunnerDevice
    |> where([srd], srd.script_runner_id == ^id)
    |> join(:inner, [srd], d in assoc(srd, :device), as: :device)
    |> order_by([device: d], asc: d.identifier)
    |> preload([device: d], device: d)
    |> Repo.all()
  end

  @doc """
  One run's device results, paginated, searchable by identifier and sortable.

  Not routed through `NervesHub.Filtering` like the other listings: that helper
  scopes every query with `product_id`, which `script_runner_devices` does not
  have. The run is the scope here, and the run itself was already fetched within
  the product's scope.
  """
  @spec filter_devices(ScriptRunner.t(), map()) :: {[ScriptRunnerDevice.t()], Flop.Meta.t()}
  def filter_devices(%ScriptRunner{id: id}, opts \\ %{}) do
    pagination = Map.get(opts, :pagination, %{})

    flop = %Flop{
      page: Map.get(pagination, :page, 1),
      page_size: Map.get(pagination, :page_size, 25)
    }

    ScriptRunnerDevice
    |> where([srd], srd.script_runner_id == ^id)
    |> join(:inner, [srd], d in assoc(srd, :device), as: :device)
    |> preload([device: d], device: d)
    |> ScriptRunnerDeviceFiltering.build_filters(Map.get(opts, :filters, %{}))
    |> ScriptRunnerDeviceFiltering.sort(Map.get(opts, :sort, {:asc, :identifier}))
    |> Flop.run(flop)
  end

  @doc """
  How many of a run's devices are at each status.
  """
  @spec status_counts(ScriptRunner.t()) :: %{ScriptRunnerDevice.status() => non_neg_integer()}
  def status_counts(%ScriptRunner{id: id}) do
    ScriptRunnerDevice
    |> where([srd], srd.script_runner_id == ^id)
    |> group_by([srd], srd.status)
    |> select([srd], {srd.status, count(srd.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Claim up to `limit` of a run's pending devices for dispatch.

  Flips the rows to `:running` and returns their device ids in one statement, so
  two dispatch jobs for the same run — a retry racing the original, say — cannot
  both take the same device. Returns `[]` when there is nothing left to claim.
  """
  @spec claim_pending_devices(integer(), pos_integer()) :: [integer()]
  def claim_pending_devices(_runner_id, limit) when limit <= 0, do: []

  def claim_pending_devices(runner_id, limit) do
    claimable =
      ScriptRunnerDevice
      |> where([srd], srd.script_runner_id == ^runner_id and srd.status == :pending)
      |> order_by([srd], asc: srd.id)
      |> limit(^limit)
      |> lock("FOR UPDATE SKIP LOCKED")
      |> select([srd], srd.id)

    {_count, device_ids} =
      ScriptRunnerDevice
      |> where([srd], srd.id in subquery(claimable))
      |> select([srd], srd.device_id)
      |> Repo.update_all(set: [status: :running, started_at: DateTime.utc_now(), updated_at: naive_now()])

    device_ids || []
  end

  @doc """
  How many devices a run still has to work through or is waiting on.
  """
  @spec unfinished_device_count(integer()) :: non_neg_integer()
  def unfinished_device_count(runner_id) do
    ScriptRunnerDevice
    |> where([srd], srd.script_runner_id == ^runner_id)
    |> where([srd], srd.status in [:pending, :running])
    |> Repo.aggregate(:count)
  end

  @doc """
  How many of a run's devices are still waiting to be dispatched.
  """
  @spec pending_device_count(integer()) :: non_neg_integer()
  def pending_device_count(runner_id) do
    ScriptRunnerDevice
    |> where([srd], srd.script_runner_id == ^runner_id and srd.status == :pending)
    |> Repo.aggregate(:count)
  end

  @doc """
  How many runs are being worked through right now.

  What the per-run share is divided by. Counts runs rather than jobs, so a run
  that has been created but not yet dispatched still takes its slice — otherwise
  the run that got there first would keep the whole budget until it finished.
  """
  @spec active_run_count() :: pos_integer()
  def active_run_count() do
    count =
      ScriptRunner
      |> where([sr], sr.status in [:pending, :running])
      |> Repo.aggregate(:count)

    max(count, 1)
  end

  @doc """
  Give a new dispatch job to any run that has lost its pacer.

  A run's pacer is inserted once, inside the transaction that creates the run, and
  `NervesHub.Workers.ScriptRunnerDispatch` keeps itself alive by snoozing. Nothing
  re-creates it: if that job is discarded — five failed attempts, or `Oban.Lifeline`
  rescuing an attempt-exhausted job — the run stops being worked through entirely.

  Left alone it does not merely stall. An unfinished run keeps counting towards
  `active_run_count/0`, which is what every other run's share of the ceiling is
  divided by, so one stranded run halves the throughput of every run after it and
  a handful of them throttle the whole fleet.

  Returns how many runs were given a new pacer. Which runs need one is asked of
  the database rather than inferred from what `Oban.insert/1` gives back, so the
  count means what it says; the dispatch worker's own uniqueness is what stops a
  duplicate if a run gains a pacer between the query and the insert.
  """
  @spec requeue_stranded_runs() :: non_neg_integer()
  def requeue_stranded_runs() do
    stranded =
      ScriptRunner
      |> where([sr], sr.status in [:pending, :running])
      |> where([sr], sr.id not in subquery(paced_run_ids()))
      |> select([sr], sr.id)
      |> Repo.all()

    jobs = Enum.map(stranded, &ScriptRunnerDispatch.new(%{script_runner_id: &1}))

    _ = Oban.insert_all(jobs)

    length(stranded)
  end

  # The runs that still have a pacer able to run. Queried the same way, and for
  # the same reason, as `live_job_device_ids/1`.
  defp paced_run_ids() do
    from(j in "oban_jobs",
      where: j.worker == ^@dispatch_worker,
      where: j.state in ^@live_job_states,
      select: type(fragment("(? ->> 'script_runner_id')::bigint", j.args), :integer)
    )
  end

  @doc """
  Record that a run has begun.
  """
  @spec mark_running(ScriptRunner.t()) :: {:ok, ScriptRunner.t()} | {:error, Changeset.t()}
  def mark_running(%ScriptRunner{} = runner) do
    runner
    |> ScriptRunner.running_changeset()
    |> Repo.update()
  end

  @doc """
  Record that every one of a run's devices reached a terminal status.
  """
  @spec mark_finished(ScriptRunner.t()) :: {:ok, ScriptRunner.t()} | {:error, Changeset.t()}
  def mark_finished(%ScriptRunner{} = runner) do
    runner
    |> ScriptRunner.finished_changeset()
    |> Repo.update()
  end

  @doc """
  Record what one device did with a run's script.
  """
  @spec record_device_result(integer(), integer(), ScriptRunnerDevice.status(), String.t() | nil) ::
          non_neg_integer()
  def record_device_result(runner_id, device_id, status, output \\ nil) do
    {count, nil} =
      ScriptRunnerDevice
      |> where([srd], srd.script_runner_id == ^runner_id and srd.device_id == ^device_id)
      |> Repo.update_all(
        set: [status: status, output: output, finished_at: DateTime.utc_now(), updated_at: naive_now()]
      )

    count
  end

  # `timestamps()` here is the repo default `:naive_datetime`, and `update_all`
  # does not cast. The status timestamps are `:utc_datetime_usec` and take a
  # `DateTime` as normal.
  defp naive_now(), do: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

  @doc """
  Which of `device_ids` are connected right now.

  One query rather than `NervesHub.Tracker.online?/1` per device: a dispatch
  batch is hundreds of devices wide. A device with no connection row has never
  connected, so it is offline.
  """
  @spec connected_device_ids([integer()]) :: [integer()]
  def connected_device_ids([]), do: []

  def connected_device_ids(device_ids) do
    Device
    |> where([d], d.id in ^device_ids)
    |> join(:left, [d], dc in assoc(d, :latest_connection), as: :latest_connection)
    |> where([latest_connection: dc], dc.status == :connected)
    |> select([d], d.id)
    |> Repo.all()
  end

  @doc """
  Watch a run's progress.

  Delivers `{:script_runner, event, payload}` to the calling process until it
  dies. See `NervesHub.ScriptRunners.PubSub` for why this is a `:group` topic
  rather than a `Phoenix.PubSub` one.
  """
  @spec subscribe(ScriptRunner.t() | integer()) :: :ok
  def subscribe(%ScriptRunner{id: id}), do: subscribe(id)
  def subscribe(id) when is_integer(id), do: PubSub.subscribe(id)

  @doc """
  Stop watching a run's progress.
  """
  @spec unsubscribe(ScriptRunner.t() | integer()) :: :ok
  def unsubscribe(%ScriptRunner{id: id}), do: unsubscribe(id)
  def unsubscribe(id) when is_integer(id), do: PubSub.unsubscribe(id)

  @doc """
  Tell subscribers a run moved on.

  Carries only what changed, so a subscriber decides for itself whether to reload
  the results — a run can be tens of thousands of devices wide.
  """
  @spec broadcast_progress(integer(), atom(), map()) :: :ok
  def broadcast_progress(runner_id, event, payload \\ %{}) do
    PubSub.broadcast(runner_id, event, payload)
  end

  @doc """
  Put a run's stuck devices back in the queue.

  A device is left at `:running` when the node executing it dies between claiming
  the row and recording an answer. Nothing else recovers that row: the device
  worker is `max_attempts: 1`, so Oban does not retry it, and `Oban.Lifeline`
  marks an attempt-exhausted job `discarded` rather than making it available
  again. The row is what `claim_pending_devices/2` looks at, so until it goes back
  to `:pending` the device is never picked up again and the run never reaches
  `:completed`.

  Only rows older than `older_than` are touched, so devices genuinely mid-script
  are left alone. The default is a wide margin over the ~31s a device job can
  live for: `NervesHub.Scripts.Runner` stops itself a second after the caller's
  timeout.

  Age alone is not enough, though. A device job waits in the `script_runners`
  queue before it runs, and on a saturated queue — or one paused through a deploy
  — that wait can outlast the cutoff while the job is perfectly healthy.
  Releasing such a row would put a second job in the queue for a device that
  already has one, and the operator's script would run on it twice. So a row is
  released only when no job is left to run it, which is what "abandoned" actually
  means.
  """
  @spec release_stale_devices(integer(), pos_integer()) :: non_neg_integer()
  def release_stale_devices(runner_id, older_than \\ to_timeout(minute: 5)) do
    cutoff = DateTime.add(DateTime.utc_now(), -older_than, :millisecond)

    {count, nil} =
      ScriptRunnerDevice
      |> where([srd], srd.script_runner_id == ^runner_id and srd.status == :running)
      |> where([srd], srd.started_at < ^cutoff)
      |> where([srd], srd.device_id not in subquery(live_job_device_ids(runner_id)))
      |> Repo.update_all(set: [status: :pending, started_at: nil, updated_at: naive_now()])

    count
  end

  # The devices this run still has a job for, in any state that can yet run it.
  # `oban_jobs` is queried as a plain table rather than through `Oban.Job`, so
  # nothing here depends on Oban's schema module.
  #
  # A `discarded` or `cancelled` job is deliberately not live: it will never run,
  # which is exactly when its row needs releasing.
  defp live_job_device_ids(runner_id) do
    from(j in "oban_jobs",
      where: j.worker == ^@device_worker,
      where: j.state in ^@live_job_states,
      where: fragment("(? ->> 'script_runner_id')::bigint = ?", j.args, ^runner_id),
      select: type(fragment("(? ->> 'device_id')::bigint", j.args), :integer)
    )
  end
end

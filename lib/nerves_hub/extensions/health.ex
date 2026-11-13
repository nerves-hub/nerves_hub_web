defmodule NervesHub.Extensions.Health do
  @moduledoc """
  Device metrics, metadata and alarms, reported on a pace this module sets.

  The platform decides when a device reports, and nothing else asks: a `check`
  goes out on one timer per connection, so however many people have the device's
  page open, the device is asked once. It used to be the other way around -- the
  Show LiveView ran its own timer and requested a check directly, on top of this
  one, once per open page -- which meant two people looking at a device asked it
  for three reports a minute between them, none of them aligned.

  The pace has two settings, and which one is in force is the `:mode` assign:

    * `:idle` -- nobody is looking. Report every `interval_minutes` (an hour by
      default), the first one offset so a fleet does not answer in unison; see
      `NervesHub.Extensions.Jitter`.
    * `:watched` -- at least one device Show LiveView is open. Report every
      `ui_polling_seconds` (a minute by default), because somebody is reading
      the numbers and a stale reading is the thing they would notice.

  Attaching asks for a report ahead of the timer: straight away while watched,
  and at a random point within `first_check_window_seconds` (a minute by
  default) otherwise, so a fleet reconnecting together does not report
  together.

  Both transitions come from `NervesHub.Extensions.PubSub`, and they are not
  symmetric: opening a page announces itself, closing one cannot. See
  `NervesHub.Extensions.PubSub.watch/2` for why each direction works the
  way it does.
  """

  @behaviour NervesHub.Extensions

  alias NervesHub.Devices.Alarms
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.HealthEvaluation.Queue, as: HealthEvaluationQueue
  alias NervesHub.Devices.Metrics
  alias NervesHub.Extensions.Jitter
  alias NervesHub.Extensions.PubSub
  alias NervesHub.Extensions.State
  alias NervesHub.Integrations
  alias NervesHub.Webhooks.Payloads

  require Logger

  @default_interval_minutes 60
  @default_ui_polling_seconds 60
  @default_first_check_window_seconds 60

  @impl NervesHub.Extensions
  def description() do
    """
    Reporting of fundamental device metrics, metadata, alarms and more.
    """
  end

  @impl NervesHub.Extensions
  def enabled?() do
    true
  end

  @impl NervesHub.Extensions
  def attach(state) do
    # Ask for a report soon, then on an interval; see `first_check/1` for how
    # soon.
    #
    # The pace is settled here rather than starting slow and being told,
    # because a page that was already open when the device connected has
    # nothing left to announce -- its join happened before there was anything
    # to announce it to.
    mode = current_mode(state)

    {State.assign(state, :mode, mode), [first_check(mode), timer(mode)]}
  end

  @impl NervesHub.Extensions
  def detach(state) do
    {State.assign(state, :mode, nil), [{:cancel_timer, :check}, {:cancel_timer, :first_check}]}
  end

  @impl NervesHub.Extensions
  def handle_in("report", %{"value" => device_report}, state) do
    device_info = state.device_info

    metrics = device_report["metrics"] || %{}

    now = DateTime.utc_now()

    # Metrics first, and not inside the health report's failure handling:
    # `Metrics.record/3` buffers rather than writing, so there is no failure
    # here to report, and a health row that will not save is no reason to throw
    # away readings that would. The buffered write is also why the judgement
    # takes the readings in hand rather than reading them back.
    {:ok, _stored} = Metrics.record(device_info, metrics, now)

    # The report carries the device's whole current alarm set; `sync/3` works
    # out which of those are new and which have cleared. Server time rather
    # than anything the device sends: a clock behind NTP would date an alarm to
    # 1970, and when the platform heard about it is the honest answer anyway.
    :ok = sync_alarms(device_info, device_report, now)

    # Metadata rides the connection, not the health row: it describes the
    # device as this connection found it, and a reconnect resets it and is
    # followed soon by a fresh report (`attach/1` sends a check ahead of the
    # timer). Straight away if somebody has the device's page open, which is
    # the only place connection metadata is read; within the first check
    # window otherwise.
    :ok = merge_metadata(device_info, device_report["metadata"])

    in_hand = for {key, value} <- metrics, is_number(value), do: {key, now, value}

    # Queued rather than run here: judging queries ClickHouse, and this call is
    # what the process holding the device's connection is waiting on. See
    # `NervesHub.Devices.HealthEvaluation.Queue`.
    :ok = HealthEvaluationQueue.enqueue(device_info, in_hand)

    :ok =
      Integrations.dispatch(device_info.product_id, "device.health_reported", fn ->
        Payloads.health_reported(device_info, Metrics.storable(metrics), device_report)
      end)

    {state, []}
  end

  @impl NervesHub.Extensions
  def handle_info(:check, state) do
    # A check is also when the pace is reconsidered, which is what makes the
    # slowdown work without anything having to announce a page closing: while
    # watched, this runs every minute, so the last person leaving costs the
    # device one extra report. Doing it here rather than on a monitor of the
    # watchers group also means the read is never racing the join it is reading
    # -- by now it has long since replicated.
    {state, effects} = reconsider(state)

    {state, [{:push, "health:check", %{}} | effects]}
  end

  # The one-off check after attaching, which is any other check.
  def handle_info(:first_check, state), do: handle_info(:check, state)

  # A device Show LiveView has opened on this device. Announced rather than
  # discovered so that speeding up does not wait on the join replicating to
  # whichever node this is running on; see
  # `NervesHub.Extensions.PubSub.watch/2`.
  def handle_info(:watching, state) do
    if State.get(state, :mode) == :watched do
      {state, []}
    else
      # Somebody has just opened the page and is looking at numbers taken up to
      # an hour ago, so this asks straight away rather than in a minute -- and
      # instead of the first check, if that has not happened yet.
      {State.assign(state, :mode, :watched), [{:cancel_timer, :first_check}, {:tick, :check}, timer(:watched)]}
    end
  end

  defp reconsider(state) do
    mode = current_mode(state)

    if mode == State.get(state, :mode) do
      {state, []}
    else
      {State.assign(state, :mode, mode), [timer(mode)]}
    end
  end

  defp current_mode(state) do
    if PubSub.watched?(device_id(state), :health), do: :watched, else: :idle
  end

  # Somebody is looking, so ask now. Only a handful of devices are watched at
  # any one time, so this is not what makes a fleet answer together.
  defp first_check(:watched), do: {:tick, :check}

  # Nobody is. A fleet reconnecting together would otherwise all report at
  # once; see `NervesHub.Extensions.Jitter`. A separate tag from `:check`, so
  # the interval timer keeps its own offset across the whole interval.
  defp first_check(:idle) do
    case first_check_window_ms() do
      0 -> {:tick, :check}
      window -> {:send_after, :first_check, Jitter.first_check_delay(window)}
    end
  end

  # Replaces whatever is armed under `:check`; see `NervesHubWeb.Channels.Effects`.
  defp timer(:watched) do
    {:start_timer, :check, to_timeout(second: ui_polling_seconds())}
  end

  defp timer(:idle) do
    interval = to_timeout(minute: health_interval_minutes())

    {:start_timer, :check, Jitter.start_delay(interval), interval}
  end

  defp device_id(state), do: state.device_info.device_id

  # A report with no `alarms` key is not saying anything about alarms, the same
  # way one with no metadata leaves the connection alone. That is what lets a
  # device on `NervesHub.Extensions.Alarms` leave them out of its health reports
  # without every report resolving what the alarms extension raised. An empty
  # map is still "none", and still resolves everything.
  defp sync_alarms(device_info, %{"alarms" => alarms}, now), do: Alarms.sync(device_info, alarms || %{}, now)
  defp sync_alarms(_device_info, _device_report, _now), do: :ok

  # Merged rather than replaced, so a report that carries only part of what the
  # device knows does not blank the rest. A report with no metadata at all
  # leaves the connection alone; an error only means the connection row has
  # already moved on, which the next report will correct.
  defp merge_metadata(_device_info, metadata) when metadata == %{}, do: :ok

  defp merge_metadata(device_info, metadata) when is_map(metadata) do
    case Connections.merge_update_metadata(device_info.connection_ref, metadata) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("[Health] failed to merge connection metadata: #{inspect(reason)}")
        :ok
    end
  end

  defp merge_metadata(_device_info, _absent_or_not_a_map), do: :ok

  defp health_interval_minutes() do
    case config([:health, :interval_minutes]) do
      i when is_integer(i) and i > 0 -> i
      _ -> @default_interval_minutes
    end
  end

  defp ui_polling_seconds() do
    case config([:health, :ui_polling_seconds]) do
      i when is_integer(i) and i > 0 -> i
      _ -> @default_ui_polling_seconds
    end
  end

  defp first_check_window_ms() do
    case config([:health, :first_check_window_seconds]) do
      i when is_integer(i) and i >= 0 -> to_timeout(second: i)
      _ -> to_timeout(second: @default_first_check_window_seconds)
    end
  end

  defp config(path) do
    :nerves_hub
    |> Application.get_env(:extension_config, [])
    |> get_in(path)
  end
end

defmodule NervesHub.Extensions.Alarms do
  @moduledoc """
  Alarms, sent by the device as they are raised and cleared.

  Version 0.1.0:

      server -> device   alarms:sync      %{}
      device -> server   alarms:snapshot  %{"alarms" => [
                           %{"alarm" => "MyApp.HighTemp", "description" => "too hot",
                             "raised_at" => "2026-09-24T02:11:09Z"},
                           ..
                         ]}
      device -> server   alarms:raised    %{"alarm" => "MyApp.HighTemp", "description" => "too hot",
                                            "raised_at" => "2026-09-24T02:11:09Z"}
      device -> server   alarms:cleared   %{"alarm" => "MyApp.HighTemp",
                                            "cleared_at" => "2026-09-24T02:40:51Z"}

  `description`, `raised_at` and `cleared_at` are optional. `docs/alarms.md`
  is the contract for client authors.

  ## Why this is not the health extension

  `NervesHub.Extensions.Health` carries alarms inside a report the platform
  asks for on a timer, so an alarm raised a minute after a report is not heard
  about until the next one -- up to an hour later on an idle device -- and one
  raised and cleared between two reports is never heard about at all. Asking
  more often only trades that delay for traffic, and most of what each report
  carries has not changed.

  An alarm is an event. The device knows the moment it happens, so it says so
  then, and the platform asks for nothing on a timer. A device that attaches
  this extension should leave `alarms` out of its health reports; `Health`
  reads an absent key as "not saying" rather than "none".

  ## Why a device still sends a set

  Events alone can drift. Anything raised or cleared while the device was
  disconnected was never sent, and a missed clear would leave an alarm on the
  device page forever. So the platform asks for the whole current set -- once,
  when the extension attaches -- and `NervesHub.Devices.Alarms.sync/3` reconciles
  it with what is stored, exactly as it does for a health report. After that,
  events keep it current.

  The same request goes out again if the platform had to drop an event (see
  "Rate limit" below), which is what makes dropping one safe.

  ## Timestamps

  The device says when, because it is often the only one who knows. An alarm
  raised during boot, before the device had connected, arrives in the attach
  snapshot minutes later; one raised while the device was offline for a day
  arrives a day later. Stamping those with arrival time would make every
  reconnect look like the moment things went wrong.

  A device's clock is not always right, though. One that has not caught up
  with NTP can say 1970, or the time its firmware was built. So a time is used
  only when it is believable -- no more than `max_future_skew_minutes/0` ahead
  of the platform's clock and no older than `max_age_days/0` -- and arrival
  time stands in otherwise. Unlike a metric reading, whose timestamp is the
  whole of what places it, an alarm with a doubtful time is still true, so
  the event is applied either way; only its time is replaced.

  The age limit is the alarm history's retention. An edge older than that
  would be expired from ClickHouse as soon as it was written.

  ## Rate limit

  One message per second with a burst of ten, per device, in a bucket of its
  own. A device that is flapping an alarm would otherwise cost a PostgreSQL
  write per flap.

  A dropped event cannot simply be forgotten, the way a dropped metric reading
  can: a lost `cleared` is an alarm that stays raised. So a denied message
  schedules a `sync`, and the device's answer replaces whatever the dropped
  events would have said. One is scheduled however many messages are denied.
  """

  @behaviour NervesHub.Extensions

  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Alarms, as: Store
  alias NervesHub.Extensions.State
  alias NervesHub.RateLimit.Alarms, as: RateLimit

  require Logger

  @rate_limit_tokens_per_sec 1
  @rate_limit_max_capacity 10
  @rate_limit_token_cost 1

  # Long enough for the bucket to have refilled by the time the device answers.
  @resync_delay_ms to_timeout(second: 10)

  @max_future_skew_minutes 60
  @max_age_days 90

  @doc "How long after a denied message the platform asks for the whole set."
  def resync_delay_ms(), do: @resync_delay_ms

  @doc "How far ahead of the platform's clock a device's time may be."
  def max_future_skew_minutes(), do: @max_future_skew_minutes

  @doc "How old a device's time may be. The alarm history's retention."
  def max_age_days(), do: @max_age_days

  @impl NervesHub.Extensions
  def description() do
    """
    Alarms sent by the device as they are raised and cleared, rather than on the Health extension's schedule.
    """
  end

  @impl NervesHub.Extensions
  def enabled?(), do: true

  @impl NervesHub.Extensions
  def attach(state) do
    {State.assign(state, :resync_pending, false), [{:push, "alarms:sync", %{}}]}
  end

  @impl NervesHub.Extensions
  def detach(state) do
    {State.assign(state, :resync_pending, false), [{:cancel_timer, :resync}]}
  end

  @impl NervesHub.Extensions
  def handle_in("snapshot", %{"alarms" => alarms}, state) when is_list(alarms) do
    if allow?(state.device_info) do
      now = DateTime.utc_now()
      :ok = Store.sync(state.device_info, entries(alarms, now), now)

      # The device has just said everything a scheduled sync would ask for.
      cancel_resync(state)
    else
      schedule_resync(state)
    end
  end

  def handle_in("raised", %{"alarm" => alarm} = payload, state) when is_binary(alarm) do
    at = device_time(payload["raised_at"], DateTime.utc_now())
    charge(state, &Store.raise_alarm(&1, alarm, payload["description"], at))
  end

  def handle_in("cleared", %{"alarm" => alarm} = payload, state) when is_binary(alarm) do
    at = device_time(payload["cleared_at"], DateTime.utc_now())
    charge(state, &Store.clear_alarm(&1, alarm, at))
  end

  # A client that declared 0.1.0 and sent something else. Worth a log line and
  # not worth a crash, and not worth a token either: nothing was going to be
  # written.
  def handle_in(event, payload, state) do
    Logger.warning(
      "device #{state.device_info.device_id} declared alarms 0.1.0 and sent #{event} #{inspect(payload, limit: 5)}"
    )

    {state, []}
  end

  @impl NervesHub.Extensions
  def handle_info(:resync, state) do
    # The timer is an interval under the hood; this is its only firing.
    {State.assign(state, :resync_pending, false), [{:cancel_timer, :resync}, {:push, "alarms:sync", %{}}]}
  end

  def handle_info(_msg, state), do: {state, []}

  @doc """
  Whether this device may send now.

  One token per message. A snapshot costs what an event costs: it is one
  transaction either way, and a device should not be put off sending the set
  that puts everything right.
  """
  @spec allow?(DeviceInfo.t()) :: boolean()
  def allow?(%DeviceInfo{} = device_info) do
    case RateLimit.hit(
           "alarms_device_#{device_info.device_id}",
           @rate_limit_tokens_per_sec,
           @rate_limit_max_capacity,
           @rate_limit_token_cost
         ) do
      {:allow, _count} -> true
      {:deny, _ms} -> false
    end
  end

  # A snapshot entry without a usable name is skipped, and its neighbours are
  # not: a device that gets one entry wrong should not lose the rest of the set.
  # That does mean a malformed entry for a raised alarm reads as "cleared",
  # which is the price of the set being authoritative.
  defp entries(alarms, now) do
    for %{"alarm" => alarm} = entry <- alarms, is_binary(alarm) do
      {alarm, entry["description"], device_time(entry["raised_at"], now)}
    end
  end

  # The device's time where it is believable, `fallback` (arrival) where it is
  # absent, unreadable, or not believable; see "Timestamps" above.
  defp device_time(timestamp, fallback) when is_binary(timestamp) do
    with {:ok, parsed, _offset} <- DateTime.from_iso8601(timestamp),
         true <- believable?(parsed, fallback) do
      parsed
    else
      _ -> fallback
    end
  end

  defp device_time(_absent, fallback), do: fallback

  # Compared in seconds, since `DateTime.diff/3` truncates larger units.
  defp believable?(timestamp, now) do
    ahead = DateTime.diff(timestamp, now, :second)

    ahead <= @max_future_skew_minutes * 60 and -ahead <= @max_age_days * 86_400
  end

  defp charge(state, write) do
    if allow?(state.device_info) do
      _ = write.(state.device_info)
      {state, []}
    else
      schedule_resync(state)
    end
  end

  defp schedule_resync(state) do
    if State.get(state, :resync_pending) do
      {state, []}
    else
      {State.assign(state, :resync_pending, true), [{:start_timer, :resync, @resync_delay_ms}]}
    end
  end

  defp cancel_resync(state) do
    if State.get(state, :resync_pending) do
      {State.assign(state, :resync_pending, false), [{:cancel_timer, :resync}]}
    else
      {state, []}
    end
  end
end

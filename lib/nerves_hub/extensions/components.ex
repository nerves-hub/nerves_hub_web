defmodule NervesHub.Extensions.Components do
  @moduledoc """
  The things a device is connected to, sent by the device as one set, and
  what they measure and what state they're in.

  Version 0.1.0:

      server -> device   components:sync      %{} | %{"refresh" => true}
      device -> server   components:snapshot  %{"components" => [
                           %{"namespace" => "zigbee", "vendor" => "1286", "model" => "SNZB-02D",
                             "serial" => "00:12:4b:00:2a:3f:91:c7", ..},
                           ..
                         ]}

  Version 0.2.0 adds, and lets a snapshot entry carry `"state" => %{name => value}`:

      device -> server   components:readings  %{"reports" => [
                           %{"namespace" => "zigbee", "serial" => "..", "timestamp" => "..",
                             "metrics" => %{"temperature" => -18.9}},
                           ..
                         ]}
      device -> server   components:state     %{"namespace" => "zwave", "serial" => "..",
                                                "state" => "lock", "value" => "unlocked", ..}

  One module serves both versions. A 0.1.0 device never sends the 0.2.0
  frames, and one that did would only have them stored.

  docs/components.md is the contract for client authors, and
  `NervesHub.Devices.Components` is where a snapshot is read and stored.

  ## Why only a set

  There are no per-component events. Components change rarely, a set is cheap
  to send whole, and a set can't drift: a missed "removed" event would leave a
  component listed for ever. The platform asks for the set when the extension
  attaches, and the device sends it again whenever anything in it changes.

  ## Rate limit

  One snapshot every ten seconds, with a burst of three, in a bucket of its
  own. A snapshot can be 500 rows to compare.

  A dropped snapshot can't simply be forgotten, since the next one may be a
  long way off. So a denied snapshot schedules a `sync`, and the device's answer
  carries whatever the dropped one said. One is scheduled however many are
  denied.

  Readings have a bucket of their own, a message a second with a burst of
  five, as `NervesHub.Extensions.Metrics` does: a dropped message is a gap in
  a chart, and the next one carries on. State changes have another, five a
  second with a burst of twenty. A dropped change would leave the wrong state
  shown, so it schedules the same `sync` a dropped snapshot does, and the
  snapshot carries the state.

  ## Components the platform hasn't been told about

  A reading or state change for a component no snapshot has listed is
  ignored, and the platform asks for the set, at most once every thirty
  seconds, so the next one is stored.
  """

  @behaviour NervesHub.Extensions

  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Components, as: Store
  alias NervesHub.Extensions.State
  alias NervesHub.RateLimit.Components, as: RateLimit

  require Logger

  # Hammer refills whole tokens per second, so ten seconds a snapshot is a
  # token a second at ten tokens a snapshot, and a burst of three is thirty.
  @rate_limit_tokens_per_sec 1
  @rate_limit_max_capacity 30
  @rate_limit_token_cost 10

  @readings_tokens_per_sec 1
  @readings_max_capacity 5

  @state_tokens_per_sec 5
  @state_max_capacity 20

  # How often an unknown component may cost the device a sync.
  @unknown_sync_interval_ms to_timeout(second: 30)

  # Long enough for the bucket to have refilled by the time the device answers.
  @resync_delay_ms to_timeout(second: 30)

  @doc "How long after a denied snapshot the platform asks for the set again."
  def resync_delay_ms(), do: @resync_delay_ms

  @impl NervesHub.Extensions
  def description() do
    """
    What the device is connected to, such as microcontrollers, Zigbee and Z-Wave nodes, and USB peripherals.
    """
  end

  @impl NervesHub.Extensions
  def enabled?(), do: true

  @impl NervesHub.Extensions
  def attach(state) do
    {State.assign(state, :resync_pending, false), [{:push, "components:sync", %{}}]}
  end

  @impl NervesHub.Extensions
  def detach(state) do
    {State.assign(state, :resync_pending, false), [{:cancel_timer, :resync}]}
  end

  @impl NervesHub.Extensions
  def handle_in("snapshot", %{"components" => components}, state) do
    now = DateTime.utc_now()

    with {:ok, entries} <- Store.parse(components, now),
         true <- allow?(state.device_info) do
      :ok = Store.sync_snapshot(state.device_info, entries, now)

      # The device has just said everything a scheduled sync would ask for.
      cancel_resync(state)
    else
      {:error, reason} ->
        Logger.warning(
          "device #{state.device_info.device_id} sent a components snapshot that was rejected (#{reason}): #{inspect(components, limit: 5)}"
        )

        {state, []}

      false ->
        schedule_resync(state)
    end
  end

  def handle_in("readings", %{"reports" => reports}, state) when is_list(reports) do
    if reports != [] and allow_readings?(state.device_info) do
      %{unknown: unknown} = Store.record_readings(state.device_info, Store.parse_readings(reports))
      sync_for_unknown(state, unknown)
    else
      {state, []}
    end
  end

  def handle_in("state", change, state) when is_map(change) do
    with true <- allow_state?(state.device_info),
         :ok <- Store.record_state(state.device_info, change) do
      {state, []}
    else
      false ->
        schedule_resync(state)

      {:error, :unknown_component} ->
        sync_for_unknown(state, 1)

      {:error, reason} ->
        Logger.warning(
          "device #{state.device_info.device_id} sent a components state change that was rejected (#{reason}): #{inspect(change, limit: 5)}"
        )

        {state, []}
    end
  end

  # Something the contract doesn't have. Worth a log line and not worth a
  # crash, and not worth a token either: nothing was going to be written.
  def handle_in(event, payload, state) do
    Logger.warning(
      "device #{state.device_info.device_id} sent components #{event}, which the contract doesn't define: #{inspect(payload, limit: 5)}"
    )

    {state, []}
  end

  @impl NervesHub.Extensions
  def handle_info(:resync, state) do
    # The timer is an interval under the hood; this is its only firing.
    {State.assign(state, :resync_pending, false), [{:cancel_timer, :resync}, {:push, "components:sync", %{}}]}
  end

  # A person asked, from the web UI, for the device to look again.
  def handle_info(:refresh, state) do
    {state, [{:push, "components:sync", %{"refresh" => true}}]}
  end

  def handle_info(_msg, state), do: {state, []}

  @doc "Whether this device may send a snapshot now."
  @spec allow?(DeviceInfo.t()) :: boolean()
  def allow?(%DeviceInfo{} = device_info) do
    case RateLimit.hit(
           "components_device_#{device_info.device_id}",
           @rate_limit_tokens_per_sec,
           @rate_limit_max_capacity,
           @rate_limit_token_cost
         ) do
      {:allow, _count} -> true
      {:deny, _ms} -> false
    end
  end

  @doc "Whether this device may send a `components:readings` message now."
  @spec allow_readings?(DeviceInfo.t()) :: boolean()
  def allow_readings?(%DeviceInfo{} = device_info) do
    hit("components_readings_device_#{device_info.device_id}", @readings_tokens_per_sec, @readings_max_capacity)
  end

  @doc "Whether this device may send a `components:state` change now."
  @spec allow_state?(DeviceInfo.t()) :: boolean()
  def allow_state?(%DeviceInfo{} = device_info) do
    hit("components_state_device_#{device_info.device_id}", @state_tokens_per_sec, @state_max_capacity)
  end

  defp hit(key, tokens_per_sec, max_capacity) do
    case RateLimit.hit(key, tokens_per_sec, max_capacity, 1) do
      {:allow, _count} -> true
      {:deny, _ms} -> false
    end
  end

  # Asks for the set straight away, unless it was asked for in the last thirty
  # seconds: a device sending readings every second for a component it forgot
  # to list shouldn't be asked every second.
  defp sync_for_unknown(state, 0), do: {state, []}

  defp sync_for_unknown(state, _unknown) do
    now = System.monotonic_time(:millisecond)
    last = State.get(state, :unknown_synced_at)

    if last && now - last < @unknown_sync_interval_ms do
      {state, []}
    else
      {State.assign(state, :unknown_synced_at, now), [{:push, "components:sync", %{}}]}
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

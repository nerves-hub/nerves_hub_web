defmodule NervesHub.Devices.AdvancedQuery.Compiler do
  @moduledoc """
  Compiles an `NervesHub.Devices.AdvancedQuery.Parser` AST into an Ecto
  query.

  Kept separate from `NervesHub.Devices.DeviceFiltering` so the advanced
  query language can be tested in isolation. Assumes the query already names
  its bindings — `device` for the devices themselves (the alarm filters
  correlate a subquery back to it) and `latest_connection` — the same
  convention `DeviceFiltering` relies on (see
  `NervesHub.Devices.common_filter_query/1`).
  """

  import Ecto.Query

  alias NervesHub.Devices.AdvancedQuery.Parser
  alias NervesHub.Devices.AdvancedQuery.Schema
  alias NervesHub.Devices.DeviceAlarm

  @not_set_value Schema.not_set_value()
  @metric_prefix Schema.metric_prefix()

  @doc "Applies the compiled AST to a query as a `where` clause."
  @spec apply_query(Ecto.Query.t(), Parser.ast()) :: Ecto.Query.t()
  def apply_query(query, ast) do
    where(query, ^to_dynamic(ast))
  end

  @doc false
  @spec to_dynamic(Parser.ast()) :: Ecto.Query.dynamic_expr()
  def to_dynamic({:and, left, right}) do
    left_dynamic = to_dynamic(left)
    right_dynamic = to_dynamic(right)
    dynamic(^left_dynamic and ^right_dynamic)
  end

  def to_dynamic({:or, left, right}) do
    left_dynamic = to_dynamic(left)
    right_dynamic = to_dynamic(right)
    dynamic(^left_dynamic or ^right_dynamic)
  end

  def to_dynamic({:not, expr}) do
    expr_dynamic = to_dynamic(expr)
    dynamic(not (^expr_dynamic))
  end

  def to_dynamic({:comparison, @metric_prefix <> key, operator, value}) do
    {number, _rest} = Float.parse(value)
    metric_dynamic(key, operator, number)
  end

  def to_dynamic({:comparison, column, operator, value}) do
    comparison_dynamic(column, operator, value)
  end

  # Compares the device's own latest reading for `key` against `value`.
  #
  # Still an `EXISTS` rather than a named binding, because `device_latest_metrics`
  # is not joined into the base query and a `dynamic/2` cannot add a join. It is
  # a much smaller one than it was: the latest set is one row per device, so the
  # inner `MAX(inserted_at)` this used to need -- which took the newest reading
  # across every device rather than this one -- is gone along with the bug in it.
  #
  # One clause per operator because `fragment/1` needs a literal string.
  defp metric_dynamic(key, ">", value) do
    dynamic(
      [d],
      fragment(
        "EXISTS (SELECT 1 FROM device_latest_metrics dlm WHERE dlm.device_id = ? AND (dlm.metrics->>?)::float > ?)",
        d.id,
        ^key,
        ^value
      )
    )
  end

  defp metric_dynamic(key, ">=", value) do
    dynamic(
      [d],
      fragment(
        "EXISTS (SELECT 1 FROM device_latest_metrics dlm WHERE dlm.device_id = ? AND (dlm.metrics->>?)::float >= ?)",
        d.id,
        ^key,
        ^value
      )
    )
  end

  defp metric_dynamic(key, "<", value) do
    dynamic(
      [d],
      fragment(
        "EXISTS (SELECT 1 FROM device_latest_metrics dlm WHERE dlm.device_id = ? AND (dlm.metrics->>?)::float < ?)",
        d.id,
        ^key,
        ^value
      )
    )
  end

  defp metric_dynamic(key, "<=", value) do
    dynamic(
      [d],
      fragment(
        "EXISTS (SELECT 1 FROM device_latest_metrics dlm WHERE dlm.device_id = ? AND (dlm.metrics->>?)::float <= ?)",
        d.id,
        ^key,
        ^value
      )
    )
  end

  # `like`/`not like` use SQL ILIKE (case-insensitive); the value is the user's
  # pattern, so they supply `%`/`_` wildcards themselves.
  defp comparison_dynamic("identifier", "like", value), do: dynamic([d], ilike(d.identifier, ^value))
  defp comparison_dynamic("identifier", "not like", value), do: dynamic([d], not ilike(d.identifier, ^value))

  # The virtual `search` column matches when any of the device's textual fields
  # matches the pattern - the same fields the sidebar free-text search covers
  # (see `NervesHub.Devices.DeviceFiltering`'s `:search` filter).
  defp comparison_dynamic("search", "like", value) do
    dynamic(
      [d],
      ilike(d.identifier, ^value) or
        ilike(fragment("COALESCE(?->>'version', '')", d.firmware_metadata), ^value) or
        ilike(fragment("COALESCE(?->>'platform', '')", d.firmware_metadata), ^value) or
        fragment(
          "string_array_to_string(COALESCE(?, ARRAY[]::text[]), ' ', ' ') ILIKE ?",
          d.tags,
          ^value
        )
    )
  end

  defp comparison_dynamic("search", "not like", value) do
    dynamic(not (^comparison_dynamic("search", "like", value)))
  end

  defp comparison_dynamic("platform", "=", value), do: dynamic([d], d.firmware_metadata["platform"] == ^value)
  defp comparison_dynamic("platform", "!=", value), do: dynamic([d], d.firmware_metadata["platform"] != ^value)

  # The value is the firmware UUID the device is currently running.
  defp comparison_dynamic("firmware", "=", value), do: dynamic([d], d.firmware_metadata["uuid"] == ^value)
  defp comparison_dynamic("firmware", "!=", value), do: dynamic([d], d.firmware_metadata["uuid"] != ^value)

  # The not-set sentinel matches devices with no deployment group.
  defp comparison_dynamic("deployment_group", "=", @not_set_value), do: dynamic([d], is_nil(d.deployment_id))
  defp comparison_dynamic("deployment_group", "!=", @not_set_value), do: dynamic([d], not is_nil(d.deployment_id))

  # The value is the deployment group name; resolve it via the device's
  # deployment_id. `!=` also matches devices with no deployment group.
  defp comparison_dynamic("deployment_group", "=", name),
    do:
      dynamic(
        [d],
        fragment("EXISTS (SELECT 1 FROM deployments dg WHERE dg.id = ? AND dg.name = ?)", d.deployment_id, ^name)
      )

  defp comparison_dynamic("deployment_group", "!=", name),
    do:
      dynamic(
        [d],
        fragment("NOT EXISTS (SELECT 1 FROM deployments dg WHERE dg.id = ? AND dg.name = ?)", d.deployment_id, ^name)
      )

  defp comparison_dynamic("architecture", "=", value), do: dynamic([d], d.firmware_metadata["architecture"] == ^value)

  defp comparison_dynamic("architecture", "!=", value), do: dynamic([d], d.firmware_metadata["architecture"] != ^value)

  # The sentinel value matches devices with no tags. `array_length` returns NULL
  # for both a NULL column and an empty array, so COALESCE treats both as 0.
  defp comparison_dynamic("tags", "contains", @not_set_value),
    do: dynamic([d], fragment("COALESCE(array_length(?, 1), 0) = 0", d.tags))

  defp comparison_dynamic("tags", "not_contains", @not_set_value),
    do: dynamic([d], fragment("COALESCE(array_length(?, 1), 0) > 0", d.tags))

  defp comparison_dynamic("tags", "contains", value),
    do: dynamic([d], fragment("? = ANY(COALESCE(?, ARRAY[]::text[]))", ^value, d.tags))

  defp comparison_dynamic("tags", "not_contains", value),
    do: dynamic([d], not fragment("? = ANY(COALESCE(?, ARRAY[]::text[]))", ^value, d.tags))

  defp comparison_dynamic("connection", "=", "not_seen"), do: dynamic([d], d.status == :registered)
  defp comparison_dynamic("connection", "!=", "not_seen"), do: dynamic([d], d.status != :registered)

  defp comparison_dynamic("connection", "=", value) do
    status = String.to_existing_atom(value)
    dynamic([latest_connection: lc], lc.status == ^status)
  end

  defp comparison_dynamic("connection", "!=", value) do
    status = String.to_existing_atom(value)
    dynamic([latest_connection: lc], is_nil(lc.status) or lc.status != ^status)
  end

  # `last_seen > "7 days ago"` => last connection more recent than the cutoff;
  # `<` => older. Devices that have never connected have a null last_seen_at and
  # match neither.
  defp comparison_dynamic("last_seen", ">", value),
    do: dynamic([latest_connection: lc], lc.last_seen_at > ^last_seen_cutoff(value) and lc.status == :disconnected)

  defp comparison_dynamic("last_seen", "<", value),
    do: dynamic([latest_connection: lc], lc.last_seen_at < ^last_seen_cutoff(value) and lc.status == :disconnected)

  # A device with no health record reads as "unknown", matching the sidebar filter.
  defp comparison_dynamic("health_status", "=", "unknown"),
    do: dynamic([latest_health: lh], lh.status == :unknown or is_nil(lh))

  defp comparison_dynamic("health_status", "=", value) do
    status = String.to_existing_atom(value)
    dynamic([latest_health: lh], lh.status == ^status)
  end

  defp comparison_dynamic("health_status", "!=", "unknown"),
    do: dynamic([latest_health: lh], not is_nil(lh) and lh.status != :unknown)

  defp comparison_dynamic("health_status", "!=", value) do
    status = String.to_existing_atom(value)
    dynamic([latest_health: lh], is_nil(lh) or lh.status != ^status)
  end

  # `network_interface` is the latest connection's reported interface, humanized
  # to one of wifi/ethernet/cellular/unknown. A device that has never connected
  # (or never reported an interface) has no value, which reads as "unknown".
  defp comparison_dynamic("connection_type", "=", "unknown"),
    do: dynamic([latest_connection: lc], lc.network_interface == :unknown or is_nil(lc.network_interface))

  defp comparison_dynamic("connection_type", "=", value) do
    interface = String.to_existing_atom(value)
    dynamic([latest_connection: lc], lc.network_interface == ^interface)
  end

  defp comparison_dynamic("connection_type", "!=", "unknown"),
    do: dynamic([latest_connection: lc], not is_nil(lc.network_interface) and lc.network_interface != :unknown)

  defp comparison_dynamic("connection_type", "!=", value) do
    interface = String.to_existing_atom(value)
    dynamic([latest_connection: lc], is_nil(lc.network_interface) or lc.network_interface != ^interface)
  end

  # "enabled" keeps meaning "not frozen", so it still matches a device that manages
  # its own updates. The two mode-specific terms tell them apart.
  defp comparison_dynamic("updates", "=", "enabled"), do: dynamic([d], d.update_mode != :off)
  defp comparison_dynamic("updates", "=", "disabled"), do: dynamic([d], d.update_mode == :off)
  defp comparison_dynamic("updates", "=", "automatic"), do: dynamic([d], d.update_mode == :automatic)

  defp comparison_dynamic("updates", "=", "device-managed"), do: dynamic([d], d.update_mode == :device_managed)

  defp comparison_dynamic("updates", "=", "penalty-box"),
    do: dynamic([d], d.updates_blocked_until > fragment("now() at time zone 'utc'"))

  defp comparison_dynamic("updates", "!=", "enabled"), do: dynamic([d], d.update_mode == :off)
  defp comparison_dynamic("updates", "!=", "disabled"), do: dynamic([d], d.update_mode != :off)
  defp comparison_dynamic("updates", "!=", "automatic"), do: dynamic([d], d.update_mode != :automatic)

  defp comparison_dynamic("updates", "!=", "device-managed"), do: dynamic([d], d.update_mode != :device_managed)

  # Devices with no penalty-box timeout (the common case) are "not penalty-box".
  defp comparison_dynamic("updates", "!=", "penalty-box"),
    do: dynamic([d], is_nil(d.updates_blocked_until) or d.updates_blocked_until <= fragment("now() at time zone 'utc'"))

  # A device is soft deleted when it has a `deleted_at` timestamp. Note that
  # `NervesHub.Filtering` drops the default "exclude deleted" filter whenever the
  # advanced query references this column, so it controls deleted visibility.
  defp comparison_dynamic("deleted", "=", "true"), do: dynamic([d], not is_nil(d.deleted_at))
  defp comparison_dynamic("deleted", "=", "false"), do: dynamic([d], is_nil(d.deleted_at))
  defp comparison_dynamic("deleted", "!=", "true"), do: dynamic([d], is_nil(d.deleted_at))
  defp comparison_dynamic("deleted", "!=", "false"), do: dynamic([d], not is_nil(d.deleted_at))

  # "with"/"without" are complementary, so `!=` maps to the opposite value. A
  # device with no health record reads as having no alarms (matching the sidebar).
  defp comparison_dynamic("alarm_status", op, "with") when op in ["=", "!="], do: alarm_status_dynamic(op == "=")

  defp comparison_dynamic("alarm_status", op, "without") when op in ["=", "!="], do: alarm_status_dynamic(op == "!=")

  # "updating" means the device has an inflight update; the two values are
  # complementary so `is not` maps to the opposite of `is`.
  defp comparison_dynamic("update_status", op, "updating") when op in ["is", "is not"],
    do: update_status_dynamic(op == "is")

  defp comparison_dynamic("update_status", op, "not updating") when op in ["is", "is not"],
    do: update_status_dynamic(op == "is not")

  # Matches a raised alarm by fuzzy text search over its name or description,
  # the same way the sidebar "Alarm" filter does. This used to run over the
  # whole health payload with `jsonb_each_text`, which also matched metadata
  # and metric values; scoped to `device_alarms` it matches only alarms, and
  # names are stored already stripped of their "Elixir." prefix.
  defp comparison_dynamic("alarm", "contains", value), do: dynamic([], exists(alarms_matching(value)))

  defp comparison_dynamic("alarm", "not_contains", value), do: dynamic([], not exists(alarms_matching(value)))

  defp alarm_status_dynamic(true), do: dynamic([], exists(raised_alarms()))

  defp alarm_status_dynamic(false), do: dynamic([], not exists(raised_alarms()))

  # Correlated on the `:device` binding the device filter query names.
  defp raised_alarms() do
    from(a in DeviceAlarm, where: a.device_id == parent_as(:device).id, select: 1)
  end

  defp alarms_matching(value) do
    pattern = "%#{value}%"

    from(a in raised_alarms(), where: ilike(a.alarm, ^pattern) or ilike(a.description, ^pattern))
  end

  defp update_status_dynamic(true), do: dynamic([inflight_update: ifu], not is_nil(ifu))
  defp update_status_dynamic(false), do: dynamic([inflight_update: ifu], is_nil(ifu))

  # Only the schema-whitelisted relative-time values reach here.
  defp last_seen_cutoff("3 days ago"), do: DateTime.add(DateTime.utc_now(), -3, :day)
  defp last_seen_cutoff("7 days ago"), do: DateTime.add(DateTime.utc_now(), -7, :day)
  defp last_seen_cutoff("14 days ago"), do: DateTime.add(DateTime.utc_now(), -14, :day)
  defp last_seen_cutoff("4 weeks ago"), do: DateTime.add(DateTime.utc_now(), -28, :day)
end

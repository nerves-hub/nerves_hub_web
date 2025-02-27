defmodule NervesHub.Devices.Filtering do
  @moduledoc """
  Encapsulates all device filtering logic
  """

  import Ecto.Query

  alias NervesHub.Devices.Alarms
  alias NervesHub.Devices.DeviceMetric
  alias NervesHub.Types.Tag

  @spec build_filters(Ecto.Query.t(), %{optional(atom) => String.t()}) :: Ecto.Query.t()
  def build_filters(query, filters) do
    Enum.reduce(filters, query, fn {key, value}, query ->
      filter(query, filters, key, value)
    end)
  end

  @spec filter(Ecto.Query.t(), %{optional(atom) => String.t()}, atom, String.t()) ::
          Ecto.Query.t()
  def filter(query, filters, key, value)

  # Filter values are empty strings as default,
  # they should be ignored.
  def filter(query, _filters, _key, "") do
    query
  end

  def filter(query, _filters, :alarm, value) do
    where(query, [d], d.id in subquery(Alarms.query_devices_with_alarm(value)))
  end

  def filter(query, _filters, :alarm_status, value) do
    case value do
      "with" -> where(query, [d], d.id in subquery(Alarms.query_devices_with_alarms()))
      "without" -> where(query, [d], d.id not in subquery(Alarms.query_devices_with_alarms()))
      _ -> query
    end
  end

  def filter(query, _filters, :health_status, value) do
    where(query, [latest_health: lh], lh.status == ^value)
  end

  def filter(query, _filters, :connection, value) do
    if value == "not_seen" do
      where(query, [d], d.status == :registered)
    else
      where(query, [latest_connection: lc], lc.status == ^value)
    end
  end

  def filter(query, _filters, :connection_type, value) do
    where(query, [latest_connection: lc], ^value in lc.metadata["connection_types"])
  end

  def filter(query, _filters, :firmware_version, value) do
    where(query, [d], d.firmware_metadata["version"] == ^value)
  end

  def filter(query, _filters, :platform, value) do
    if value == "Unknown" do
      where(query, [d], is_nil(d.firmware_metadata["platform"]))
    else
      where(query, [d], d.firmware_metadata["platform"] == ^value)
    end
  end

  def filter(query, _filters, :updates, value) do
    case value do
      "enabled" ->
        where(query, [d], d.updates_enabled == true)

      "penalty-box" ->
        where(query, [d], d.updates_blocked_until > fragment("now() at time zone 'utc'"))

      "disabled" ->
        where(query, [d], d.updates_enabled == false)
    end
  end

  def filter(query, _filters, :device_id, value) do
    where(query, [d], ilike(d.identifier, ^"%#{value}%"))
  end

  def filter(query, _filters, :deployment_id, nil), do: query

  def filter(query, _filters, :deployment_id, value) do
    where(query, [d], d.deployment_id == ^value)
  end

  def filter(query, _filters, :tag, value) do
    build_tag_filter(query, value)
  end

  def filter(query, _filters, :has_no_tags, value) do
    if value do
      where(query, [d], fragment("array_length(?, 1) = 0 or ? IS NULL", d.tags, d.tags))
    else
      query
    end
  end

  def filter(query, filters, :metrics_key, _value) do
    filter_on_metric(query, filters)
  end

  def filter(query, _filters, :is_pinned, value) do
    if value do
      where(query, [pinned: pd], not is_nil(pd))
    else
      query
    end
  end

  # Ignore any undefined filter.
  # This will prevent error 500 responses on deprecated saved bookmarks etc.
  def filter(query, _filters, _key, _value) do
    query
  end

  defp build_tag_filter(query, value) do
    case Tag.cast(value) do
      {:ok, tags} ->
        Enum.reduce(tags, query, fn tag, query ->
          where(
            query,
            [d],
            fragment("string_array_to_string(?, ' ', ' ') ILIKE ?", d.tags, ^"%#{tag}%")
          )
        end)

      {:error, _} ->
        query
    end
  end

  defp filter_on_metric(
         query,
         %{metrics_key: key, metrics_operator: operator, metrics_value: value}
       )
       when key != "" and value != "" do
    {value_as_float, _} = Float.parse(value)

    query
    |> join(:inner, [d], m in DeviceMetric, on: d.id == m.device_id, as: :device_metric)
    |> where([device_metric: dm], dm.inserted_at == subquery(latest_metric_for_key(key)))
    |> where([device_metric: dm], dm.key == ^key)
    |> gt_or_lt(value_as_float, operator)
  end

  defp filter_on_metric(query, _), do: query

  defp latest_metric_for_key(key) do
    DeviceMetric
    |> select([dm], max(dm.inserted_at))
    |> where([dm], dm.key == ^key)
  end

  defp gt_or_lt(query, value, "gt"), do: where(query, [device_metric: dm], dm.value > ^value)
  defp gt_or_lt(query, value, "lt"), do: where(query, [device_metric: dm], dm.value < ^value)
end

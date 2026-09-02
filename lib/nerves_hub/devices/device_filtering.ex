defmodule NervesHub.Devices.DeviceFiltering do
  @moduledoc """
  Encapsulates all device filtering and sorting logic
  """

  import Ecto.Query

  alias NervesHub.Devices.AdvancedQuery.Compiler
  alias NervesHub.Devices.AdvancedQuery.Schema
  alias NervesHub.Types.Tag

  @default_filters %{
    connection: "",
    connection_type: "",
    firmware_version: "",
    platform: "",
    healthy: "",
    health_status: "",
    identifier: "",
    tags: "",
    updates: "",
    has_no_tags: false,
    alarm_status: "",
    alarm: "",
    metrics_key: "",
    metrics_operator: "gt",
    metrics_value: "",
    deployment_id: "",
    is_pinned: false,
    search: "",
    display_deleted: "exclude",
    only_updating: false,
    advanced_query: ""
  }

  @filter_types %{
    connection: :string,
    connection_type: :string,
    firmware_version: :string,
    platform: :string,
    healthy: :string,
    health_status: :string,
    identifier: :string,
    tags: :string,
    updates: :string,
    has_no_tags: :boolean,
    alarm_status: :string,
    alarm: :string,
    metrics_key: :string,
    metrics_operator: :string,
    metrics_value: :string,
    deployment_id: :string,
    is_pinned: :boolean,
    search: :string,
    display_deleted: :string,
    only_updating: :boolean,
    advanced_query: :string
  }

  @default_sort %{sort_direction: "asc", sort: "identifier"}
  @sort_types %{sort_direction: :string, sort: :string}
  @sortable_fields ~w(identifier connection_established_at connection_last_seen_at tags)
  @sort_directions ~w(asc desc)

  def default_filters(), do: @default_filters

  def default_sort(), do: @default_sort

  @doc """
  Casts raw (string-keyed) params into the filter map, applying defaults for
  any missing values.
  """
  def parse_filters(params) do
    Map.merge(@default_filters, filter_changes(params))
  end

  @doc """
  Casts raw (string-keyed) params into a sort opts map, applying defaults for
  any missing/invalid values.
  """
  def parse_sort(params) do
    @default_sort
    |> Map.merge(sort_changes(params))
    |> validate_sort()
  end

  defp validate_sort(%{sort: sort} = sort_opts) when sort not in @sortable_fields do
    validate_sort(%{sort_opts | sort: @default_sort.sort})
  end

  defp validate_sort(%{sort_direction: direction} = sort_opts) when direction not in @sort_directions do
    %{sort_opts | sort_direction: @default_sort.sort_direction}
  end

  defp validate_sort(sort_opts), do: sort_opts

  def transform_deployment_filter(%{deployment_id: ""} = filters), do: Map.delete(filters, :deployment_id)

  def transform_deployment_filter(%{deployment_id: "-1"} = filters), do: %{filters | deployment_id: nil}

  def transform_deployment_filter(filters), do: %{filters | deployment_id: String.to_integer(filters.deployment_id)}

  @doc """
  Casts raw (string-keyed) params into only the filter fields present in
  `params`, without filling in defaults for missing ones.
  """
  def filter_changes(params) do
    # when the metrics key is switched from being selected to being an empty value,
    # the metrics value is not cleared, this addresses that.
    params =
      if params["metrics_key"] == "" do
        params
        |> Map.put("metrics_operator", "gt")
        |> Map.put("metrics_value", "")
      else
        params
      end

    Ecto.Changeset.cast({@default_filters, @filter_types}, params, Map.keys(@default_filters), empty_values: []).changes
  end

  @doc """
  Casts raw (string-keyed) params into only the sort fields present in
  `params`, without filling in defaults for missing ones.
  """
  def sort_changes(params) do
    Ecto.Changeset.cast({@default_sort, @sort_types}, params, Map.keys(@default_sort)).changes
  end

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

  def filter(query, _filters, :alarm, alarm) do
    advanced(query, "alarm", "contains", alarm)
  end

  def filter(query, _filters, :alarm_status, value) when value in ["with", "without"] do
    advanced(query, "alarm_status", "=", value)
  end

  def filter(query, _filters, :health_status, value) do
    advanced(query, "health_status", "=", value)
  end

  def filter(query, _filters, :connection, "not_seen_in_seven_days") do
    advanced(query, "last_seen", "<", "7 days ago")
  end

  def filter(query, _filters, :connection, "not_seen_in_fourteen_days") do
    advanced(query, "last_seen", "<", "14 days ago")
  end

  def filter(query, _filters, :connection, value) do
    advanced(query, "connection", "=", value)
  end

  def filter(query, _filters, :connection_type, value) do
    advanced(query, "connection_type", "=", value)
  end

  # The advanced query's `firmware` column matches by UUID, not version, so
  # this stays a direct comparison.
  def filter(query, _filters, :firmware_version, value) do
    where(query, [d], d.firmware_metadata["version"] == ^value)
  end

  def filter(query, _filters, :platform, "Unknown") do
    where(query, [d], is_nil(d.firmware_metadata["platform"]))
  end

  def filter(query, _filters, :platform, value) do
    advanced(query, "platform", "=", value)
  end

  def filter(query, _filters, :updates, value)
      when value in ["enabled", "penalty-box", "disabled", "automatic", "device-managed"] do
    advanced(query, "updates", "=", value)
  end

  def filter(query, _filters, :identifier, value) do
    advanced(query, "identifier", "like", "%#{value}%")
  end

  def filter(query, _filters, :deployment_id, nil) do
    where(query, [d], is_nil(d.deployment_id))
  end

  def filter(query, _filters, :deployment_id, value) do
    where(query, [d], d.deployment_id == ^value)
  end

  def filter(query, _filters, :tags, value) do
    build_tag_filter(query, value)
  end

  def filter(query, _filters, :has_no_tags, value) do
    if value do
      advanced(query, "tags", "contains", Schema.not_set_value())
    else
      query
    end
  end

  def filter(query, filters, :metrics_key, _value) do
    filter_on_metric(query, filters)
  end

  def filter(query, _filters, :display_deleted, "include"), do: order_by(query, [d], asc_nulls_last: d.deleted_at)

  def filter(query, _filters, :display_deleted, "exclude"), do: advanced(query, "deleted", "=", "false")

  def filter(query, _filters, :display_deleted, "only"), do: advanced(query, "deleted", "=", "true")

  def filter(query, _filters, :only_updating, false), do: query

  def filter(query, _filters, :only_updating, true), do: advanced(query, "update_status", "is", "updating")

  def filter(query, _filters, :search, value) when is_binary(value) and value != "" do
    advanced(query, "search", "like", "%#{value}%")
  end

  # Ignore any undefined filter.
  # This will prevent error 500 responses on deprecated saved bookmarks etc.
  def filter(query, _filters, _key, _value) do
    query
  end

  @spec sort(Ecto.Query.t(), {atom(), atom()}) :: Ecto.Query.t()
  def sort(query, {:asc, :connection_established_at}) do
    order_by(query, [latest_connection: latest_connection], desc_nulls_last: latest_connection.established_at)
  end

  def sort(query, {:desc, :connection_established_at}) do
    order_by(query, [latest_connection: latest_connection], asc_nulls_first: latest_connection.established_at)
  end

  def sort(query, {:asc, :connection_last_seen_at}) do
    order_by(query, [latest_connection: latest_connection], desc_nulls_last: latest_connection.last_seen_at)
  end

  def sort(query, {:desc, :connection_last_seen_at}) do
    order_by(query, [latest_connection: latest_connection], asc_nulls_first: latest_connection.last_seen_at)
  end

  def sort(query, sort), do: order_by(query, [], ^sort)

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

  defp filter_on_metric(query, %{metrics_key: key, metrics_operator: operator, metrics_value: value})
       when key != "" and value != "" do
    advanced(query, Schema.metric_prefix() <> key, metric_operator(operator), value)
  end

  defp filter_on_metric(query, _), do: query

  defp metric_operator("lt"), do: "<"
  defp metric_operator(_), do: ">"

  defp advanced(query, column, operator, value) do
    where(query, ^Compiler.to_dynamic({:comparison, column, operator, value}))
  end
end

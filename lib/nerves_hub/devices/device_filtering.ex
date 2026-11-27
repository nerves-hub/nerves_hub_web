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
    firmware_validation_status: "",
    signer_ca: "",
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
    advanced_query: "",
    state: "",
    reason: ""
  }

  @filter_types %{
    connection: :string,
    connection_type: :string,
    firmware_version: :string,
    firmware_validation_status: :string,
    signer_ca: :string,
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
    advanced_query: :string,
    state: :string,
    reason: :string
  }

  # The devices list's tabs, each a slice of the product's devices. "" is All.
  @states ~w(attention online updating offline)

  # Why a device is in the Needs attention tab, each one of its filters.
  @reasons ~w(unhealthy failing not_seen)

  # Not seen for this many days, a device needs attention.
  @not_seen_days 14

  # Filters that take several choices at once, comma-separated: a device
  # matches any of them. Each choice is a `value_dynamic/2`.
  @multi_filters [
    :health_status,
    :connection,
    :connection_type,
    :firmware_version,
    :updates,
    :firmware_validation_status,
    :alarm_status,
    :alarm
  ]

  @type multi_filter() ::
          :health_status
          | :connection
          | :connection_type
          | :firmware_version
          | :updates
          | :firmware_validation_status
          | :alarm_status
          | :alarm

  @type sort_field() :: :identifier | :connection_established_at | :connection_last_seen_at | :tags

  @type sort_direction() :: :asc | :desc

  # The values of each filter that takes one of a fixed set. A multi-choice
  # filter takes one or more, comma-separated, and `value_dynamic/2` is what
  # applies each; a value listed here must be one it applies.
  @filter_values %{
    alarm_status: ~w(with without),
    connection: ~w(connected offline asleep disconnected not_seen not_seen_in_seven_days not_seen_in_fourteen_days),
    connection_type: ~w(cellular ethernet wifi unknown),
    display_deleted: ~w(exclude include only),
    firmware_validation_status: ~w(validated not_validated unknown),
    health_status: ~w(healthy warning unhealthy unknown),
    metrics_operator: ~w(gt lt),
    reason: @reasons,
    state: @states,
    updates: ~w(enabled disabled automatic device-managed penalty-box failed-updates updating)
  }

  # A deployment group's ID is a bigint.
  @max_deployment_id 9_223_372_036_854_775_807

  @default_sort %{sort_direction: "asc", sort: "identifier"}
  @sort_types %{sort_direction: :string, sort: :string}
  @sort_fields ~w(identifier connection_established_at connection_last_seen_at tags)a
  @sortable_fields Enum.map(@sort_fields, &Atom.to_string/1)
  @sort_direction_atoms ~w(asc desc)a
  @sort_directions Enum.map(@sort_direction_atoms, &Atom.to_string/1)

  # Each sort field and direction under the name a request gives it, so that
  # `cast_sort/2` looks it up rather than making an atom from the request.
  @sort_names %{
    sort: Map.new(@sort_fields, &{Atom.to_string(&1), &1}),
    sort_direction: Map.new(@sort_direction_atoms, &{Atom.to_string(&1), &1})
  }

  def default_filters(), do: @default_filters

  def default_sort(), do: @default_sort

  @doc "The fields the devices list can be sorted by."
  @spec sort_fields() :: [sort_field(), ...]
  def sort_fields(), do: @sort_fields

  @doc "The directions the devices list can be sorted in."
  @spec sort_directions() :: [String.t(), ...]
  def sort_directions(), do: @sort_directions

  @doc """
  The values a filter takes, for one that takes one of a fixed set, or nil
  for one that takes any text, a number, or true or false. A filter in
  `multi_filters/0` takes one or more of them, comma-separated.
  """
  @spec filter_values(atom()) :: [String.t(), ...] | nil
  def filter_values(key), do: Map.get(@filter_values, key)

  @doc "The states the devices list has a tab for, besides All."
  @spec states() :: [String.t()]
  def states(), do: @states

  @doc """
  The devices in one of the devices list's tabs, as a condition on the query
  `NervesHub.Devices.filter/3` builds:

    * `"attention"` - unhealthy, stopped taking updates after repeated
      failures, or not seen in #{@not_seen_days} days
    * `"online"` - connected now
    * `"updating"` - installing an update now
    * `"offline"` - not connected now, including devices never seen
  """
  @spec state_dynamic(String.t()) :: Ecto.Query.dynamic_expr()
  def state_dynamic("attention") do
    Enum.reduce(@reasons, dynamic(false), fn reason, acc -> dynamic(^acc or ^reason_dynamic(reason)) end)
  end

  def state_dynamic("online"), do: Compiler.to_dynamic({:comparison, "connection", "=", "connected"})
  def state_dynamic("updating"), do: Compiler.to_dynamic({:comparison, "update_status", "is", "updating"})
  def state_dynamic("offline"), do: Compiler.to_dynamic({:comparison, "connection", "!=", "connected"})

  @doc "The reasons a device can need attention, each a filter of the Needs attention tab."
  @spec reasons() :: [String.t()]
  def reasons(), do: @reasons

  @doc """
  How many days a device can go unseen before it needs attention (the
  `"not_seen"` reason). The devices list's rows and peek say why a device is
  on the Needs attention tab, so they use this rather than a number of their own.
  """
  def not_seen_days(), do: @not_seen_days

  @doc "`not_seen_days/0` in seconds."
  def not_seen_seconds(), do: @not_seen_days * 86_400

  @doc """
  The devices that need attention for one reason, as a condition on the query
  `NervesHub.Devices.filter/3` builds:

    * `"unhealthy"` - its health is unhealthy
    * `"failing"` - its updates are on hold after repeated failures
    * `"not_seen"` - last seen #{@not_seen_days} days ago or more
  """
  @spec reason_dynamic(String.t()) :: Ecto.Query.dynamic_expr()
  def reason_dynamic("unhealthy"), do: Compiler.to_dynamic({:comparison, "health_status", "=", "unhealthy"})
  def reason_dynamic("failing"), do: Compiler.to_dynamic({:comparison, "updates", "=", "failed-updates"})
  def reason_dynamic("not_seen"), do: Compiler.to_dynamic({:comparison, "last_seen", "<", "#{@not_seen_days} days ago"})

  @doc """
  The filters that take several choices at once, as a comma-separated value.
  A device matches the filter when it matches any of its choices.
  """
  @spec multi_filters() :: [multi_filter(), ...]
  def multi_filters(), do: @multi_filters

  @doc "A multi-choice filter's value as its list of choices."
  @spec choices(String.t()) :: [String.t()]
  def choices(value) when is_binary(value), do: String.split(value, ",", trim: true)
  def choices(_value), do: []

  @doc """
  The devices matching one choice of a multi-choice filter
  (`multi_filters/0`), as a condition on the query `NervesHub.Devices.filter/3`
  builds, or nil for a choice the filter doesn't have.
  """
  @spec value_dynamic(atom(), String.t()) :: Ecto.Query.dynamic_expr() | nil
  def value_dynamic(:health_status, value) when value in ~w(healthy warning unhealthy unknown),
    do: comparison("health_status", "=", value)

  def value_dynamic(:connection, "not_seen_in_seven_days"), do: comparison("last_seen", "<", "7 days ago")
  def value_dynamic(:connection, "not_seen_in_fourteen_days"), do: comparison("last_seen", "<", "14 days ago")

  # Not connected now, as the Offline tab counts it: "disconnected" leaves out
  # devices that never connected.
  def value_dynamic(:connection, "offline"), do: state_dynamic("offline")

  # Asleep: the last connection ended with the device saying it was going to
  # sleep, overdue or not.
  def value_dynamic(:connection, value) when value in ~w(connected disconnected not_seen asleep),
    do: comparison("connection", "=", value)

  def value_dynamic(:connection_type, value) when value in ~w(cellular ethernet wifi unknown),
    do: comparison("connection_type", "=", value)

  def value_dynamic(:firmware_version, "Unknown"), do: dynamic([d], is_nil(d.firmware_metadata["version"]))

  # The advanced query's `firmware` column matches by UUID, not version, so
  # this stays a direct comparison.
  def value_dynamic(:firmware_version, value), do: dynamic([d], d.firmware_metadata["version"] == ^value)

  def value_dynamic(:updates, "updating"), do: comparison("update_status", "is", "updating")

  def value_dynamic(:updates, value)
      when value in ["enabled", "penalty-box", "failed-updates", "disabled", "automatic", "device-managed"],
      do: comparison("updates", "=", value)

  def value_dynamic(:firmware_validation_status, value) when value in ["validated", "not_validated", "unknown"],
    do: comparison("firmware_validation_status", "=", value)

  def value_dynamic(:alarm_status, value) when value in ["with", "without"], do: comparison("alarm_status", "=", value)
  def value_dynamic(:alarm, value), do: comparison("alarm", "contains", value)
  def value_dynamic(_key, _value), do: nil

  defp comparison(column, operator, value), do: Compiler.to_dynamic({:comparison, column, operator, value})

  @doc """
  Casts raw (string-keyed) params into the filter map, applying defaults for
  any missing values.
  """
  def parse_filters(params) do
    Map.merge(@default_filters, filter_changes(params))
  end

  @doc """
  Casts an API request's (string-keyed) filters into the filter map, as
  `parse_filters/1` casts the web UI's, defaults included.

  The web UI drops what it can't use, so that an old link still opens. This
  refuses it instead: a key that isn't a filter, or a value its filter can't
  take, such as `has_no_tags=maybe`, a choice `filter_values/1` doesn't list,
  or a `deployment_id` that isn't an ID. An empty value leaves its filter
  unset, as it does in the web UI.

  ## Examples

      iex> {:ok, filters} = cast_filters(%{"has_no_tags" => "false", "connection" => "connected,asleep"})
      iex> Map.take(filters, [:has_no_tags, :connection, :display_deleted])
      %{has_no_tags: false, connection: "connected,asleep", display_deleted: "exclude"}

      iex> cast_filters(%{"tag" => "prod"})
      {:error, {:unknown_filter, "tag"}}

      iex> cast_filters(%{"only_updating" => "yes"})
      {:error, {:invalid_filter, :only_updating, "must be true or false"}}
  """
  @spec cast_filters(%{optional(String.t()) => term()}) ::
          {:ok, map()}
          | {:error, {:unknown_filter, String.t()} | {:invalid_filter, atom(), String.t()}}
  def cast_filters(params) when is_map(params) do
    params = Map.reject(params, fn {_key, value} -> value == "" end)
    known = Enum.map(Map.keys(@default_filters), &Atom.to_string/1)

    with [] <- Enum.sort(Map.keys(params) -- known),
         %{valid?: true, changes: changes} <- params |> filters_changeset() |> validate_filter_values() do
      {:ok, Map.merge(@default_filters, changes)}
    else
      [key | _] -> {:error, {:unknown_filter, key}}
      %{errors: errors} -> invalid_filter(errors)
    end
  end

  # Ecto adds errors in front, so the one reported is picked by key to be the
  # same whatever order the filters came in.
  defp invalid_filter(errors) do
    {key, {message, opts}} = Enum.min_by(errors, &elem(&1, 0))

    message =
      case {opts[:validation], opts[:type]} do
        {:cast, :boolean} -> "must be true or false"
        {:cast, _type} -> "must be a string"
        _other -> message
      end

    {:error, {:invalid_filter, key, message}}
  end

  defp validate_filter_values(changeset) do
    Enum.reduce(changeset.changes, changeset, fn {key, value}, changeset ->
      case filter_value_error(key, value) do
        nil -> changeset
        message -> Ecto.Changeset.add_error(changeset, key, message)
      end
    end)
  end

  defp filter_value_error(key, value) when key in @multi_filters do
    if Enum.any?(choices(value), &is_nil(value_dynamic(key, &1))) do
      "must be one or more of #{list_values(key)}, comma-separated"
    end
  end

  defp filter_value_error(key, value) when is_map_key(@filter_values, key) do
    if value not in @filter_values[key], do: "must be one of #{list_values(key)}"
  end

  defp filter_value_error(:deployment_id, "-1"), do: nil

  defp filter_value_error(:deployment_id, value) do
    case Integer.parse(value) do
      {id, ""} when id >= 1 and id <= @max_deployment_id -> nil
      _other -> "must be a deployment group's ID, or -1 for devices in none"
    end
  end

  defp filter_value_error(:metrics_value, value) do
    case Float.parse(value) do
      {_number, ""} -> nil
      _other -> "must be a number"
    end
  end

  defp filter_value_error(:tags, value) do
    case Tag.cast(value) do
      {:ok, _tags} -> nil
      {:error, message: message} -> message
    end
  end

  defp filter_value_error(_key, _value), do: nil

  defp list_values(key), do: Enum.join(@filter_values[key], ", ")

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

  @doc """
  Casts an API request's sort field and direction into the `{direction, field}`
  the devices list sorts by, as `parse_sort/1` casts the web UI's.

  The web UI falls back to the default for a field or direction it doesn't
  know. This refuses it instead, naming which of the two it was. Either can be
  left out (nil or empty), and the default sort fills it in.

  ## Examples

      iex> cast_sort("connection_last_seen_at", "desc")
      {:ok, {:desc, :connection_last_seen_at}}

      iex> cast_sort(nil, "desc")
      {:ok, {:desc, :identifier}}

      iex> cast_sort("inserted_at", nil)
      {:error, {:invalid_sort, :sort, "inserted_at"}}
  """
  @spec cast_sort(term(), term()) ::
          {:ok, {sort_direction(), sort_field()}} | {:error, {:invalid_sort, :sort | :sort_direction, term()}}
  def cast_sort(field, direction) do
    with {:ok, field} <- sort_name(:sort, field),
         {:ok, direction} <- sort_name(:sort_direction, direction) do
      {:ok, {direction, field}}
    end
  end

  defp sort_name(key, value) when value in [nil, ""], do: sort_name(key, @default_sort[key])

  defp sort_name(key, value) do
    case Map.fetch(@sort_names[key], value) do
      {:ok, name} -> {:ok, name}
      :error -> {:error, {:invalid_sort, key, value}}
    end
  end

  def transform_deployment_filter(%{deployment_id: ""} = filters), do: Map.delete(filters, :deployment_id)

  def transform_deployment_filter(%{deployment_id: "-1"} = filters), do: %{filters | deployment_id: nil}

  def transform_deployment_filter(filters), do: %{filters | deployment_id: String.to_integer(filters.deployment_id)}

  @doc """
  Casts raw (string-keyed) params into only the filter fields present in
  `params`, without filling in defaults for missing ones.
  """
  def filter_changes(params), do: filters_changeset(params).changes

  defp filters_changeset(params) do
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

    Ecto.Changeset.cast({@default_filters, @filter_types}, params, Map.keys(@default_filters), empty_values: [])
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

  def filter(query, _filters, key, value) when key in @multi_filters and is_binary(value) do
    value
    |> choices()
    |> Enum.map(&value_dynamic(key, &1))
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> query
      [first | rest] -> where(query, ^Enum.reduce(rest, first, fn choice, acc -> dynamic(^acc or ^choice) end))
    end
  end

  # The value is the signer CA's serial, or the not-set sentinel for devices
  # with no certificate from a CA registered with this org.
  def filter(query, _filters, :signer_ca, value) do
    advanced(query, "signer_ca", "=", value)
  end

  def filter(query, _filters, :platform, "Unknown") do
    where(query, [d], is_nil(d.firmware_metadata["platform"]))
  end

  def filter(query, _filters, :platform, value) do
    advanced(query, "platform", "=", value)
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

  # Pins are each web UI user's own, so only a query joined to the user's
  # pins as `:pinned` can apply this. Any other, such as the API's device
  # list, ignores it, as it does every filter it can't apply.
  def filter(query, _filters, :is_pinned, true) do
    if has_named_binding?(query, :pinned) do
      where(query, [pinned: pd], not is_nil(pd.id))
    else
      query
    end
  end

  def filter(query, _filters, :display_deleted, "include"), do: order_by(query, [d], asc_nulls_last: d.deleted_at)

  def filter(query, _filters, :display_deleted, "exclude"), do: advanced(query, "deleted", "=", "false")

  def filter(query, _filters, :display_deleted, "only"), do: advanced(query, "deleted", "=", "true")

  def filter(query, _filters, :only_updating, false), do: query

  def filter(query, _filters, :only_updating, true), do: advanced(query, "update_status", "is", "updating")

  def filter(query, _filters, :state, value) when value in @states, do: where(query, ^state_dynamic(value))
  def filter(query, _filters, :reason, value) when value in @reasons, do: where(query, ^reason_dynamic(value))

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

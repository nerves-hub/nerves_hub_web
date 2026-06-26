defmodule NervesHub.Devices.AdvancedQuery.Schema do
  @moduledoc """
  Whitelist of columns, operators, and value sources for the device list
  advanced query language.

  This is intentionally separate from `NervesHub.Devices.DeviceFiltering`
  (the sidebar/basic search filters) so the query language can evolve and be
  tested independently.
  """

  alias NervesHub.Devices
  alias NervesHub.Devices.Alarms
  alias NervesHub.Firmwares
  alias NervesHub.ManagedDeployments

  # Shared sentinel value meaning "no value" / not set, used by nullable columns
  # (e.g. tags with no tags, or a device with no deployment group). The leading
  # colon makes a collision with a real value very unlikely; the compiler
  # special-cases it per column.
  @not_set_value ":not_set"

  # Metrics are queried with a dynamic column of the form `metric:<key>`, e.g.
  # `metric:cpu_temp > 10`. The operators are numeric comparisons and the value
  # is a freeform number rather than a predefined list. Any non-empty key is
  # accepted (devices report arbitrary keys); the autosuggest is driven by the
  # keys actually present for the product (see the live view's schema JSON).
  @metric_prefix "metric:"
  @metric_operators [">", ">=", "<", "<="]

  # Columns whose value is freeform text (a SQL LIKE pattern) rather than one of
  # a predefined set - so any non-empty value is accepted and there is nothing
  # to autosuggest.
  @freeform_text_columns ["identifier"]

  @columns %{
    "identifier" => %{
      operators: ["like", "not like"],
      values: &__MODULE__.no_values/1
    },
    "platform" => %{
      operators: ["=", "!="],
      values: &Devices.platforms/1
    },
    # The value is a full firmware UUID; the live view's schema JSON shows a
    # friendlier "<version> - <short uuid>" label in the autosuggest.
    "firmware" => %{
      operators: ["=", "!="],
      values: &__MODULE__.firmware_values/1
    },
    "architecture" => %{
      operators: ["=", "!="],
      values: &Devices.architectures/1
    },
    "connection" => %{
      operators: ["=", "!="],
      values: &__MODULE__.connection_values/1
    },
    # The value is a relative time; `last_seen > "7 days ago"` means the device's
    # last connection is more recent than 7 days ago, `<` means older (stale).
    "last_seen" => %{
      operators: [">", "<"],
      values: &__MODULE__.last_seen_values/1
    },
    "tags" => %{
      operators: ["contains", "not_contains"],
      values: &__MODULE__.tag_values/1
    },
    "health_status" => %{
      operators: ["=", "!="],
      values: &__MODULE__.health_status_values/1
    },
    "connection_type" => %{
      operators: ["=", "!="],
      values: &__MODULE__.connection_type_values/1
    },
    "updates" => %{
      operators: ["=", "!="],
      values: &__MODULE__.updates_values/1
    },
    "alarm_status" => %{
      operators: ["=", "!="],
      values: &__MODULE__.alarm_status_values/1
    },
    "alarm" => %{
      operators: ["contains", "not_contains"],
      values: &Alarms.get_current_alarm_types/1
    },
    "deleted" => %{
      operators: ["=", "!="],
      values: &__MODULE__.boolean_values/1
    },
    "update_status" => %{
      operators: ["is", "is not"],
      values: &__MODULE__.update_status_values/1
    },
    # The value is the deployment group name (or the not-set sentinel for devices
    # with no deployment group); the compiler resolves it to the device's group.
    "deployment_group" => %{
      operators: ["=", "!="],
      values: &__MODULE__.deployment_group_values/1
    }
  }

  @doc "The fixed (non-metric) whitelisted column names, for autosuggest."
  @spec columns() :: [String.t()]
  def columns(), do: Map.keys(@columns)

  @doc "Whether the column is whitelisted."
  @spec column?(String.t()) :: boolean()
  def column?(column), do: Map.has_key?(@columns, column) or metric_column?(column)

  @doc "The whitelisted operators for a column, or `:error` if the column is unknown."
  @spec operators(String.t()) :: [String.t()] | :error
  def operators(column) do
    if metric_column?(column) do
      @metric_operators
    else
      case Map.fetch(@columns, column) do
        {:ok, %{operators: operators}} -> operators
        :error -> :error
      end
    end
  end

  @doc "Whether the operator is valid for the given column."
  @spec operator?(String.t(), String.t()) :: boolean()
  def operator?(column, operator) do
    case operators(column) do
      :error -> false
      operators -> operator in operators
    end
  end

  @doc """
  The predefined values available for a column, scoped to a product, or
  `:error` if the column is unknown. Metric columns take freeform numbers and
  so have no predefined values.
  """
  @spec values(String.t(), pos_integer()) :: [String.t()] | :error
  def values(column, product_id) do
    if metric_column?(column) do
      []
    else
      case Map.fetch(@columns, column) do
        {:ok, %{values: values_fun}} -> values_fun.(product_id)
        :error -> :error
      end
    end
  end

  @doc """
  Whether the value is valid for the column - a predefined value for normal
  columns, any number for metric columns, or any non-empty string for freeform
  text columns.
  """
  @spec value?(String.t(), String.t(), pos_integer()) :: boolean()
  def value?(column, value, product_id) do
    cond do
      metric_column?(column) ->
        number?(value)

      column in @freeform_text_columns ->
        value != ""

      true ->
        case values(column, product_id) do
          :error -> false
          values -> value in values
        end
    end
  end

  @doc "The `metric:` column prefix."
  @spec metric_prefix() :: String.t()
  def metric_prefix(), do: @metric_prefix

  @doc false
  def no_values(_product_id), do: []

  @doc false
  def firmware_values(product_id) do
    product_id
    |> Firmwares.firmware_versions_and_uuids()
    |> Enum.map(& &1.uuid)
  end

  defp metric_column?(@metric_prefix <> key), do: key != ""
  defp metric_column?(_column), do: false

  defp number?(value) do
    case Float.parse(value) do
      {_number, ""} -> true
      _ -> false
    end
  end

  @doc false
  def connection_values(_product_id), do: ["connected", "disconnected", "not_seen"]

  @doc false
  def last_seen_values(_product_id), do: ["3 days ago", "7 days ago", "14 days ago", "4 weeks ago"]

  @doc false
  def health_status_values(_product_id), do: ["unknown", "healthy", "warning", "unhealthy"]

  @doc false
  def connection_type_values(_product_id), do: ["cellular", "ethernet", "wifi", "unknown"]

  @doc false
  def updates_values(_product_id), do: ["enabled", "disabled", "penalty-box"]

  @doc false
  def alarm_status_values(_product_id), do: ["with", "without"]

  @doc false
  def boolean_values(_product_id), do: ["true", "false"]

  @doc false
  def update_status_values(_product_id), do: ["updating", "not updating"]

  @doc "The shared \"not set\" sentinel value used by nullable columns."
  @spec not_set_value() :: String.t()
  def not_set_value(), do: @not_set_value

  @doc false
  def tag_values(product_id), do: Devices.distinct_tags(product_id) ++ [@not_set_value]

  @doc false
  def deployment_group_values(product_id) do
    ManagedDeployments.deployment_group_names(product_id) ++ [@not_set_value]
  end
end

defmodule NervesHub.Devices.AdvancedQuery.SidebarSync do
  @moduledoc """
  Keeps the sidebar filter controls and the advanced query in sync.

  Sidebar filters the query language can express are stored in the
  `advanced_query` itself rather than as their own URL params: changing a
  control rewrites the query's top-level `and` chain (`merge/3`), and the
  controls display their state by reading it back out (`derive/2`).

  A control only claims a comparison it could have written itself, and only
  when the top-level `and` chain holds exactly one node matching its
  pattern. Anything else - an `or`/`not` expression, a duplicated column, an
  operator the sidebar can't produce - is left alone, shows as unset in the
  sidebar, and survives further sidebar edits untouched.
  """

  alias NervesHub.Devices.AdvancedQuery
  alias NervesHub.Devices.AdvancedQuery.Schema

  @health_status_values ~w(unknown healthy warning unhealthy)
  @connection_values ~w(connected disconnected not_seen)
  @connection_type_values ~w(cellular ethernet wifi unknown)
  @updates_values ~w(enabled penalty-box disabled automatic device-managed)
  @alarm_status_values ~w(with without)

  # Form fields stored in the advanced query, with the value they reset to in
  # the URL params once their state has moved into the query.
  @synced_field_defaults %{
    "identifier" => "",
    "health_status" => "",
    "connection" => "",
    "connection_type" => "",
    "updates" => "",
    "platform" => "",
    "alarm_status" => "",
    "alarm" => "",
    "has_no_tags" => "false",
    "only_updating" => "false",
    "metrics_key" => "",
    "metrics_operator" => "gt",
    "metrics_value" => ""
  }

  @doc """
  Rewrites `query` to reflect the sidebar form `params`.

  Returns `{:ok, new_query, params}` with the synced fields in `params` reset
  to their defaults (so they drop out of the URL), or `:error` when the
  current query does not parse - the caller then leaves the update alone
  rather than guessing at surgery on a broken query.
  """
  @spec merge(map(), String.t() | nil, pos_integer()) :: {:ok, String.t(), map()} | :error
  def merge(params, query, product_id) do
    case and_chain(query, product_id) do
      {:ok, nodes} ->
        claimed = nodes |> claims() |> Map.values() |> MapSet.new(fn {index, _values} -> index end)

        kept =
          nodes
          |> Enum.with_index()
          |> Enum.reject(fn {_node, index} -> MapSet.member?(claimed, index) end)
          |> Enum.map(fn {node, _index} -> print(node) end)

        {:ok, Enum.join(kept ++ encode(params), " and "), reset_synced_fields(params)}

      :error ->
        :error
    end
  end

  @doc """
  The sidebar control values encoded in the query, keyed like the filter map,
  for displaying the controls' state.
  """
  @spec derive(String.t() | nil, pos_integer()) :: map()
  def derive(query, product_id) do
    case and_chain(query, product_id) do
      {:ok, nodes} ->
        nodes
        |> claims()
        |> Enum.reduce(%{}, fn {_group, {_index, values}}, acc -> Map.merge(acc, values) end)

      :error ->
        %{}
    end
  end

  defp and_chain(query, product_id) do
    case String.trim(query || "") do
      "" ->
        {:ok, []}

      query ->
        case AdvancedQuery.interpret(query, product_id) do
          {:ok, _canonical, ast} -> {:ok, flatten_and(ast)}
          {:error, _message, _position} -> :error
        end
    end
  end

  defp flatten_and({:and, left, right}), do: flatten_and(left) ++ flatten_and(right)
  defp flatten_and(node), do: [node]

  # Claimable nodes grouped by the control they belong to; a control claims
  # its node only when it matched exactly one.
  defp claims(nodes) do
    nodes
    |> Enum.with_index()
    |> Enum.flat_map(fn {node, index} ->
      case decode(node) do
        nil -> []
        {group, values} -> [{group, {index, values}}]
      end
    end)
    |> Enum.group_by(fn {group, _claim} -> group end, fn {_group, claim} -> claim end)
    |> Enum.flat_map(fn
      {group, [claim]} -> [{group, claim}]
      {_group, _ambiguous} -> []
    end)
    |> Map.new()
  end

  defp decode({:comparison, "identifier", "like", pattern}) do
    with "%" <> rest <- pattern,
         inner when inner != "" <- String.slice(rest, 0..-2//1),
         "%" <- String.last(rest) do
      {:identifier, %{identifier: inner}}
    else
      _ -> nil
    end
  end

  defp decode({:comparison, "health_status", "=", value}) when value in @health_status_values,
    do: {:health_status, %{health_status: value}}

  defp decode({:comparison, "connection", "=", value}) when value in @connection_values,
    do: {:connection, %{connection: value}}

  defp decode({:comparison, "last_seen", "<", "7 days ago"}), do: {:connection, %{connection: "not_seen_in_seven_days"}}

  defp decode({:comparison, "last_seen", "<", "14 days ago"}),
    do: {:connection, %{connection: "not_seen_in_fourteen_days"}}

  defp decode({:comparison, "connection_type", "=", value}) when value in @connection_type_values,
    do: {:connection_type, %{connection_type: value}}

  defp decode({:comparison, "updates", "=", value}) when value in @updates_values, do: {:updates, %{updates: value}}

  defp decode({:comparison, "platform", "=", value}), do: {:platform, %{platform: value}}

  defp decode({:comparison, "alarm_status", "=", value}) when value in @alarm_status_values,
    do: {:alarm_status, %{alarm_status: value}}

  defp decode({:comparison, "alarm", "contains", value}), do: {:alarm, %{alarm: value}}

  defp decode({:comparison, "tags", "contains", value}) do
    if value == Schema.not_set_value(), do: {:has_no_tags, %{has_no_tags: true}}
  end

  defp decode({:comparison, "update_status", "is", "updating"}), do: {:only_updating, %{only_updating: true}}

  defp decode({:comparison, column, operator, value}) when operator in [">", "<"] do
    case column do
      "metric:" <> key ->
        operator = if operator == ">", do: "gt", else: "lt"
        {:metrics, %{metrics_key: key, metrics_operator: operator, metrics_value: value}}

      _ ->
        nil
    end
  end

  defp decode(_node), do: nil

  defp encode(params) do
    []
    |> encode_value(params, "identifier", fn value -> comparison("identifier", "like", "%#{value}%") end)
    |> encode_value(params, "health_status", @health_status_values, "=")
    |> encode_connection(params)
    |> encode_value(params, "connection_type", @connection_type_values, "=")
    |> encode_value(params, "updates", @updates_values, "=")
    |> encode_value(params, "platform", fn
      "Unknown" -> nil
      value -> comparison("platform", "=", value)
    end)
    |> encode_value(params, "alarm_status", @alarm_status_values, "=")
    |> encode_value(params, "alarm", fn value -> comparison("alarm", "contains", value) end)
    |> encode_value(params, "has_no_tags", fn
      "true" -> comparison("tags", "contains", Schema.not_set_value())
      _ -> nil
    end)
    |> encode_value(params, "only_updating", fn
      "true" -> comparison("update_status", "is", "updating")
      _ -> nil
    end)
    |> encode_metrics(params)
    |> Enum.reverse()
  end

  defp encode_value(acc, params, field, allowed, operator) when is_list(allowed) do
    encode_value(acc, params, field, fn value ->
      if value in allowed, do: comparison(field, operator, value)
    end)
  end

  defp encode_value(acc, params, field, encoder) when is_function(encoder, 1) do
    case Map.get(params, field, "") do
      "" -> acc
      value -> prepend(acc, encoder.(value))
    end
  end

  defp encode_connection(acc, params) do
    encode_value(acc, params, "connection", fn
      "not_seen_in_seven_days" -> comparison("last_seen", "<", "7 days ago")
      "not_seen_in_fourteen_days" -> comparison("last_seen", "<", "14 days ago")
      value when value in @connection_values -> comparison("connection", "=", value)
      _ -> nil
    end)
  end

  defp encode_metrics(acc, %{"metrics_key" => key, "metrics_value" => value} = params) when key != "" and value != "" do
    operator = if params["metrics_operator"] == "lt", do: "<", else: ">"
    prepend(acc, "#{Schema.metric_prefix()}#{key} #{operator} #{value}")
  end

  defp encode_metrics(acc, _params), do: acc

  defp prepend(acc, nil), do: acc
  defp prepend(acc, clause), do: [clause | acc]

  defp comparison(column, operator, value) do
    escaped = value |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"")
    ~s(#{column} #{operator} "#{escaped}")
  end

  # A half-filled metrics trio (key chosen, value still empty) has no query
  # representation yet but drives the sidebar's operator/value inputs, so it
  # stays in the params until the comparison is complete.
  defp reset_synced_fields(params) do
    resets = Map.take(@synced_field_defaults, Map.keys(params))

    resets =
      if Map.get(params, "metrics_key", "") != "" and Map.get(params, "metrics_value", "") == "" do
        Map.drop(resets, ["metrics_key", "metrics_operator", "metrics_value"])
      else
        resets
      end

    Map.merge(params, resets)
  end

  # Reprints an unclaimed node. Comparisons print bare; compound expressions
  # are parenthesized so joining the chain with `and` cannot change meaning.
  defp print({:comparison, "metric:" <> _ = column, operator, value}), do: "#{column} #{operator} #{value}"

  defp print({:comparison, column, operator, value}), do: comparison(column, operator, value)

  defp print(node), do: "(" <> print_expression(node) <> ")"

  defp print_expression({:and, left, right}), do: print_operand(left) <> " and " <> print_operand(right)

  defp print_expression({:or, left, right}), do: print_operand(left) <> " or " <> print_operand(right)

  defp print_expression({:not, expression}), do: "not " <> print_operand(expression)

  defp print_expression(comparison), do: print(comparison)

  defp print_operand({:comparison, _column, _operator, _value} = comparison), do: print(comparison)
  defp print_operand(node), do: "(" <> print_expression(node) <> ")"
end

defmodule NervesHubWeb.API.DeviceMetricController do
  @moduledoc """
  The metric history a device has reported, over the `health` or `metrics`
  extension.

  Read-only. Readings arrive on the device's own connection and there is no way
  to write one here.

  Answers in reports, the shape the device sent them in: one timestamp and the
  readings taken at it. A report can be narrowed to some of its metrics, and
  the history to a window of time.

  History is kept in the analytics database for thirty days. A deployment with
  no analytics database has no history to read, and says so rather than
  answering with an empty list.
  """

  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Devices.Metrics

  security([%{"bearer_auth" => []}])
  tags(["Device Metrics"])

  @default_limit 100
  @max_limit 1000

  plug(:validate_role, [org: :view] when action in [:index])

  # OpenAPI specs for :index can be found in DeviceMetricControllerSpecs, which
  # documents the product-scoped and the short device URL separately.
  operation(:index, [])

  def index(%{assigns: %{device: device}} = conn, params) do
    with :ok <- analytics_enabled(),
         {:ok, opts} <- query_opts(params) do
      render(conn, :index, reports: Metrics.reports_for_device(device, opts))
    end
  end

  defp analytics_enabled() do
    if Application.get_env(:nerves_hub, :analytics_enabled) do
      :ok
    else
      {:error,
       {:analytics_not_enabled,
        "This platform has no analytics database configured, so device metric history is not stored. " <>
          "Contact your Ops team for more information."}}
    end
  end

  defp query_opts(params) do
    with {:ok, keys} <- keys(params["key"]),
         {:ok, since} <- timestamp("since", params["since"]),
         {:ok, before} <- timestamp("before", params["before"]),
         {:ok, limit} <- limit(params["limit"]),
         {:ok, order} <- order(params["order"]) do
      {:ok, [keys: keys, since: since, before: before, limit: limit, order: order]}
    end
  end

  # Metric names are the device's own, so nothing here is checked against a
  # list — a name no device has reported is a filter that matches nothing
  # rather than an error.
  defp keys(nil), do: {:ok, nil}

  defp keys(key) when is_binary(key) do
    key
    |> String.split(",")
    |> keys()
  end

  defp keys(keys) when is_list(keys) do
    if Enum.all?(keys, &is_binary/1) do
      case Enum.reject(Enum.map(keys, &String.trim/1), &(&1 == "")) do
        [] -> {:ok, nil}
        keys -> {:ok, keys}
      end
    else
      invalid_keys(keys)
    end
  end

  defp keys(key), do: invalid_keys(key)

  defp invalid_keys(key), do: {:error, {:invalid_query_param, "key must be a string, got #{inspect(key)}."}}

  defp timestamp(_name, nil), do: {:ok, nil}
  defp timestamp(_name, ""), do: {:ok, nil}

  defp timestamp(name, value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, timestamp, _offset} ->
        {:ok, timestamp}

      {:error, _reason} ->
        {:error,
         {:invalid_query_param,
          "#{name} must be an ISO 8601 timestamp, eg. 2026-08-16T09:14:00Z, got #{inspect(value)}."}}
    end
  end

  defp timestamp(name, value) do
    {:error, {:invalid_query_param, "#{name} must be an ISO 8601 timestamp, got #{inspect(value)}."}}
  end

  defp limit(nil), do: {:ok, @default_limit}
  defp limit(""), do: {:ok, @default_limit}

  defp limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {parsed, ""} -> validate_limit(parsed, limit)
      _other -> invalid_limit(limit)
    end
  end

  defp limit(limit), do: invalid_limit(limit)

  defp validate_limit(limit, _raw) when limit >= 1 and limit <= @max_limit, do: {:ok, limit}
  defp validate_limit(_limit, raw), do: invalid_limit(raw)

  defp invalid_limit(raw) do
    {:error, {:invalid_query_param, "limit must be a whole number between 1 and #{@max_limit}, got #{inspect(raw)}."}}
  end

  defp order(nil), do: {:ok, :desc}
  defp order(""), do: {:ok, :desc}
  defp order("desc"), do: {:ok, :desc}
  defp order("asc"), do: {:ok, :asc}

  defp order(order), do: {:error, {:invalid_query_param, "order must be asc or desc, got #{inspect(order)}."}}
end

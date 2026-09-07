defmodule NervesHubWeb.API.DeviceLogController do
  @moduledoc """
  The log lines a device has sent over the logging extension.

  Read-only. Log lines arrive on the device's own connection and there is no
  way to write one here.

  Lines can be narrowed by level, by a window of time, and by a search term
  matched against the message text.

  Whether the logging extension is currently enabled for the product or the
  device governs whether new lines arrive, not whether stored ones can be read,
  so turning it off leaves everything collected before that still readable.
  A deployment with no analytics database configured has nothing to read from
  at all, and says so rather than answering with an empty list.

  Log lines are dropped three days after they were logged, so this only ever
  answers for the recent past.
  """

  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Devices.LogLines

  security([%{"bearer_auth" => []}])
  tags(["Device Logs"])

  @default_limit 100
  @max_limit 1000

  plug(:validate_role, [org: :view] when action in [:index])

  # OpenAPI specs for :index can be found in DeviceLogControllerSpecs, which
  # documents the product-scoped and the short device URL separately.
  operation(:index, [])

  def index(%{assigns: %{device: device}} = conn, params) do
    with :ok <- analytics_enabled(),
         {:ok, opts} <- query_opts(params) do
      render(conn, :index, log_lines: LogLines.for_device(device, opts))
    end
  end

  defp analytics_enabled() do
    if Application.get_env(:nerves_hub, :analytics_enabled) do
      :ok
    else
      {:error, :analytics_not_enabled}
    end
  end

  defp query_opts(params) do
    with {:ok, levels} <- levels(params["level"]),
         {:ok, search} <- search(params["search"]),
         {:ok, since} <- timestamp("since", params["since"]),
         {:ok, before} <- timestamp("before", params["before"]),
         {:ok, limit} <- limit(params["limit"]),
         {:ok, order} <- order(params["order"]) do
      {:ok, [levels: levels, search: search, since: since, before: before, limit: limit, order: order]}
    end
  end

  # A device is free to log at any level it likes, so nothing here is checked
  # against a fixed list — an unrecognised level is a filter that matches
  # nothing rather than an error.
  defp levels(nil), do: {:ok, nil}

  defp levels(level) when is_binary(level) do
    level
    |> String.split(",")
    |> levels()
  end

  defp levels(levels) when is_list(levels) do
    case Enum.reject(Enum.map(levels, &String.trim/1), &(&1 == "")) do
      [] -> {:ok, nil}
      levels -> {:ok, levels}
    end
  end

  defp levels(level), do: {:error, {:invalid_query_param, "level must be a string, got #{inspect(level)}."}}

  # Matched literally against the message, ignoring case. Only the surrounding
  # whitespace is trimmed — whitespace inside the term is part of what the
  # caller is looking for.
  defp search(nil), do: {:ok, nil}

  defp search(search) when is_binary(search) do
    case String.trim(search) do
      "" -> {:ok, nil}
      trimmed -> {:ok, trimmed}
    end
  end

  defp search(search), do: {:error, {:invalid_query_param, "search must be a string, got #{inspect(search)}."}}

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

  defp limit(limit) when is_integer(limit), do: validate_limit(limit, limit)

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

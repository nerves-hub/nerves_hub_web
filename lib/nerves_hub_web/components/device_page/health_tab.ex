defmodule NervesHubWeb.Components.DevicePage.HealthTab do
  use NervesHubWeb, tab_component: :health

  alias NervesHub.Devices.Metrics

  @time_frame_opts [
    {"hour", 3},
    {"day", 1},
    {"day", 7}
  ]
  @default_time_frame {"hour", 3}

  # Metric types with belonging titles to display as default.
  # Also sets order of charts.
  @default_metrics [
    {"load_1min", "Load Average 1 Min"},
    {"load_5min", "Load Average 5 Min"},
    {"load_15min", "Load Average 15 Min"},
    {"mem_used_mb", "Memory Usage (MB)"},
    {"mem_used_percent", "Memory Usage (%)"},
    {"disk_used_percentage", "Disk Usage (%)"},
    {"cpu_usage_percent", "CPU Usage (%)"},
    {"cpu_temp", "CPU Temperature (°C)"}
  ]

  @manual_metrics [
    "cpu_temp",
    "cpu_usage_percent",
    "mem_used_mb",
    "mem_size_mb",
    "mem_used_percent",
    "load_1min",
    "load_5min",
    "load_15min",
    "timestamp"
  ]

  # Will not be rendered as chart.
  @no_chart_metrics [
    "mem_size_mb",
    "disk_total_kb"
  ]

  @tick_interval 55_000

  def tab_params(_params, _uri, socket) do
    _ = if connected?(socket), do: Process.send_after(self(), :tick, @tick_interval)

    socket
    |> update_from_and_until_timestamps()
    |> assign(:time_frame_opts, @time_frame_opts)
    |> assign(:latest_metrics, Metrics.get_latest_metric_set(socket.assigns.device.id))
    |> async_assign_charts()
    |> cont()
  end

  def cleanup() do
    [:time_frame, :time_frame_opts, :charts]
  end

  def hooked_async("update_chart:" <> key, {:ok, results}, socket) do
    {from, until} = fetch_from_and_until(socket)

    socket
    |> assign(has_chart_data_key(key), Enum.any?(results))
    |> push_event("update-charts", %{
      key: key,
      data: results,
      from: from,
      until: until,
      unit: get_time_unit(socket.assigns.time_frame)
    })
    |> halt()
  end

  def hooked_async("update_chart:" <> key, {:exit, reason}, socket) do
    _ =
      Sentry.capture_message("Unexpected error when updating device health charts",
        extra: %{key: key, reason: reason},
        result: :none
      )

    halt(socket)
  end

  def hooked_async(_name, _async_fun_result, socket), do: {:cont, socket}

  def hooked_event("set-time-frame", %{"unit" => unit, "amount" => amount}, socket) do
    {parsed_amount, ""} = Integer.parse(amount)

    socket
    |> assign(:time_frame, {validate_time_unit(unit), parsed_amount})
    |> update_from_and_until_timestamps()
    |> update_charts()
    |> halt()
  end

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  def hooked_info(%Broadcast{event: "health_check_report"}, %{assigns: %{device: device}} = socket) do
    latest_metrics = Metrics.get_latest_metric_set(device.id)

    chart_keys = metrics_to_chart(socket.assigns.latest_metrics)

    socket =
      socket
      |> update_from_and_until_timestamps()
      |> assign(:latest_metrics, latest_metrics)
      |> assign_metadata()

    {from, until} = fetch_from_and_until(socket)

    # if we previously didn't loaded any metric keys, now is the time to do it
    if Enum.empty?(chart_keys) do
      async_assign_charts(socket)
    else
      latest_metrics
      |> metrics_to_chart()
      |> Enum.reduce(socket, fn key, socket ->
        data = %{
          x: DateTime.to_unix(latest_metrics["timestamp"], :millisecond),
          y: latest_metrics[key]
        }

        socket
        |> push_event("add-data-point", %{key: key, data: data, from: from, until: until})
        |> assign(has_chart_data_key(key), true)
      end)
    end
    |> halt()
  end

  def hooked_info(:tick, socket) do
    Process.send_after(self(), :tick, @tick_interval)

    socket
    |> update_from_and_until_timestamps()
    |> then(fn socket ->
      {from, until} = fetch_from_and_until(socket)
      push_event(socket, "update-time-frame", %{from: from, until: until})
    end)
    |> halt()
  end

  def hooked_info(_event, socket), do: {:cont, socket}

  def render(assigns) do
    health_enabled = assigns.product.extensions.health && assigns.device.extensions.health

    assigns = Map.put(assigns, :health_enabled?, health_enabled)

    ~H"""
    <div
      id="health-tab"
      phx-mounted={JS.remove_class("opacity-0")}
      class="phx-click-loading:opacity-50 tab-content size-full p-6 opacity-0 transition-all duration-500"
    >
      <div :if={Enum.any?(@latest_metrics) && @health_enabled?} class="bg-base-900 border-base-700 mb-6 flex w-full flex-col rounded border">
        <div class="shadow-device-details-content flex flex-col">
          <div class="flex flex-wrap items-center justify-items-stretch gap-2 px-4 pt-2 pb-4">
            <div class="border-success health-good flex h-16 grow flex-col rounded border-b px-3 py-2">
              <span class="text-base-400 text-xs tracking-wide">CPU</span>
              <div :if={@latest_metrics["cpu_usage_percent"] && @latest_metrics["cpu_temp"]} class="flex items-end justify-between">
                <span class="text-base-50 text-xl leading-[30px]">{round(@latest_metrics["cpu_usage_percent"])}%</span>
                <span class="text-success text-base">{round(@latest_metrics["cpu_temp"])}°</span>
              </div>
              <div :if={@latest_metrics["cpu_usage_percent"] && !@latest_metrics["cpu_temp"]} class="flex items-end justify-between">
                <span class="text-base-50 text-xl leading-[30px]">{round(@latest_metrics["cpu_usage_percent"])}%</span>
              </div>
              <div :if={!@latest_metrics["cpu_usage_percent"] && @latest_metrics["cpu_temp"]} class="flex items-end justify-between">
                <span class="text-base-50 text-xl leading-[30px]">{round(@latest_metrics["cpu_temp"])}°</span>
              </div>
              <span :if={!@latest_metrics["cpu_usage_percent"] && !@latest_metrics["cpu_temp"]} class="text-nerves-gray-500 text-xl leading-[30px]">NA</span>
            </div>
            <div class="border-warning health-warning flex h-16 grow flex-col rounded border-b px-3 py-2">
              <span class="text-base-400 text-xs tracking-wide">Memory used</span>
              <div :if={@latest_metrics["mem_used_mb"]} class="flex items-end justify-between">
                <span class="text-base-50 text-xl leading-[30px]">{round(@latest_metrics["mem_used_mb"])}MB</span>
                <span class="text-warning text-base">{round(@latest_metrics["mem_used_percent"])}%</span>
              </div>
              <div :if={!@latest_metrics["mem_used_mb"]} class="flex items-end justify-between">
                <span class="text-nerves-gray-500 text-xl leading-[30px]">Not reported</span>
              </div>
            </div>
            <div class="border-primary health-neutral flex h-16 grow flex-col rounded border-b px-3 py-2">
              <span class="text-base-400 text-xs tracking-wide">Load avg</span>
              <div :if={@latest_metrics["load_1min"] || @latest_metrics["load_5min"] || @latest_metrics["load_15min"]} class="flex items-center justify-between">
                <span :if={@latest_metrics["load_1min"]} class="text-base-50 text-xl leading-[30px]">{@latest_metrics["load_1min"]}</span>
                <span :if={!@latest_metrics["load_1min"]} class="text-nerves-gray-500 text-xl leading-[30px]">NA</span>
                <span class="bg-base-700 h-4 w-px"></span>
                <span :if={@latest_metrics["load_5min"]} class="text-base-50 text-xl leading-[30px]">{@latest_metrics["load_5min"]}</span>
                <span :if={!@latest_metrics["load_5min"]} class="text-nerves-gray-500 text-xl leading-[30px]">NA</span>
                <span class="bg-base-700 h-4 w-px"></span>
                <span :if={@latest_metrics["load_15min"]} class="text-base-50 text-xl leading-[30px]">{@latest_metrics["load_15min"]}</span>
                <span :if={!@latest_metrics["load_15min"]} class="text-nerves-gray-500 text-xl leading-[30px]">NA</span>
              </div>
              <div :if={!@latest_metrics["load_1min"] && !@latest_metrics["load_5min"] && !@latest_metrics["load_15min"]} class="flex items-center">
                <span class="text-nerves-gray-500 text-xl leading-[30px]">Not reported</span>
              </div>
            </div>
            <div :for={{key, value} <- custom_metrics(@latest_metrics)} class="health-plain flex h-16 grow flex-col rounded border-b border-neutral-500 px-3 py-2">
              <span class="text-base-400 text-xs tracking-wide">{key_label(key)}</span>
              <span class="text-base-50 text-xl leading-[30px]">{nice_round(value)}</span>
            </div>
          </div>
        </div>
      </div>

      <div :if={Enum.any?(Map.keys(@latest_metrics))} class="bg-base-900 border-base-700 flex w-full flex-col rounded border">
        <div class="border-base-700 flex h-14 items-center justify-between border-b px-4">
          <div class="flex items-end gap-3">
            <div class="text-base-50 text-base font-medium">Health over time</div>
            <div :if={@latest_metrics["timestamp"]} class="text-nerves-gray-500 mr-auto text-xs tracking-wide">
              <span>Last updated: </span>
              <time id="health-last-updated" phx-hook="UpdatingTimeAgo" datetime={String.replace(DateTime.to_string(DateTime.truncate(@latest_metrics["timestamp"], :second)), " ", "T")}>
                {Timex.from_now(@latest_metrics["timestamp"])}
              </time>
            </div>
          </div>
          <div class="inline-flex rounded-md shadow-sm" role="group">
            <button
              :for={{unit, amount} <- @time_frame_opts}
              type="button"
              class={[
                "border-base-600 hover:bg-base-700 hover:text-base-200 cursor-pointer border px-4 py-2 text-sm font-medium first:rounded-s-lg last:rounded-e-lg focus:z-10 focus:ring-0",
                {unit, amount} != @time_frame && "bg-base-800 text-base-300",
                {unit, amount} == @time_frame && "bg-base-700 text-base-200"
              ]}
              aria-label={Integer.to_string(amount) <> " " <> unit <> if amount > 1, do: "s", else: ""}
              type="button"
              phx-click="set-time-frame"
              phx-value-unit={unit}
              phx-value-amount={amount}
            >
              {Integer.to_string(amount) <> " " <> unit <> if amount > 1, do: "s", else: ""}
            </button>
          </div>
        </div>

        <div class="flex flex-col gap-10 p-10">
          <div :for={key <- metrics_to_chart(@latest_metrics)} class="flex flex-col gap-3">
            <div class="relative flex h-[200px] w-full">
              <.async_result :let={chart_data} assign={assigns[chart_data_key(key)]}>
                <:loading>
                  <div class="bg-base-900/70 absolute inset-0 flex items-center justify-center">
                    <span class="text-base-500 font-extralight">Loading history for {key}...</span>
                  </div>
                </:loading>
                <:failed :let={_failure}>
                  <div class="bg-base-900/70 absolute inset-0 flex items-center justify-center">
                    <span class="text-base-500 font-extralight">Sorry, there was an error loading the history for {key}.</span>
                  </div>
                </:failed>
                <canvas
                  id={key <> "-chart"}
                  phx-hook="Chart"
                  phx-update="ignore"
                  data-key={key}
                  data-metrics={Jason.encode!(chart_data)}
                  data-title={title(key)}
                  data-max={suggested_max(key)}
                  data-mintime={Jason.encode!(@charts_from_timestamp)}
                  data-maxtime={Jason.encode!(@charts_until_timestamp)}
                  data-unit="minute"
                ></canvas>
                <div :if={not assigns[has_chart_data_key(key)] && Enum.empty?(chart_data)} class="bg-base-900/70 absolute inset-0 flex items-center justify-center">
                  <span class="text-base-500 font-extralight">No metrics for {key} found for the selected period.</span>
                </div>
              </.async_result>
            </div>
          </div>
        </div>
      </div>

      <div :if={Enum.empty?(Map.keys(@latest_metrics))} class="bg-base-900 border-base-700 flex size-full flex-col rounded border">
        <div class="border-base-700 flex h-14 shrink-0 items-center justify-between border-b px-4">
          <div class="flex items-end gap-3">
            <div class="text-base-50 text-base font-medium">Health over time</div>
          </div>
          <div class="inline-flex rounded-md shadow-sm" role="group">
            <button
              :for={{unit, amount} <- @time_frame_opts}
              type="button"
              class={[
                "border-base-600 border px-4 py-2 text-sm font-medium first:rounded-s-lg last:rounded-e-lg focus:z-10 focus:ring-0",
                {unit, amount} != @time_frame && "bg-base-800 text-base-300",
                {unit, amount} == @time_frame && "bg-base-700 text-base-200"
              ]}
              aria-label={Integer.to_string(amount) <> " " <> unit <> if amount > 1, do: "s", else: ""}
              type="button"
              disabled
              phx-click="set-time-frame"
              phx-value-unit={unit}
              phx-value-amount={amount}
            >
              {Integer.to_string(amount) <> " " <> unit <> if amount > 1, do: "s", else: ""}
            </button>
          </div>
        </div>

        <div class="flex h-full flex-col items-center justify-center gap-10 p-10">
          <div class="text-base-500 flex flex-col gap-3">
            No health metrics have been received from the device
          </div>
        </div>
      </div>

      <div :if={Enum.any?(Map.keys(@latest_metrics))} class="h-6"></div>
    </div>
    """
  end

  defp update_from_and_until_timestamps(socket) do
    {unit, unit_amount} = Map.get(socket.assigns, :time_frame, @default_time_frame)

    from = DateTime.add(DateTime.utc_now(), -unit_amount, String.to_existing_atom(unit))
    until = DateTime.utc_now()

    socket
    |> assign(:time_frame, {unit, unit_amount})
    |> assign(:charts_from_timestamp, from)
    |> assign(:charts_until_timestamp, until)
  end

  defp update_charts(socket) do
    %{device: %{id: device_id}, time_frame: time_frame, latest_metrics: latest_metrics} = socket.assigns

    latest_metrics
    |> metrics_to_chart()
    |> Enum.reduce(socket, fn key, socket ->
      start_async(socket, "update_chart:#{key}", fn ->
        formatted_metrics(device_id, key, time_frame)
      end)
    end)
  end

  defp async_assign_charts(socket) do
    device_id = socket.assigns.device.id
    time_frame = socket.assigns.time_frame

    socket.assigns.latest_metrics
    |> metrics_to_chart()
    |> Enum.reduce(socket, fn key, socket ->
      socket
      |> assign_async(chart_data_key(key), fn ->
        {:ok, %{chart_data_key(key) => formatted_metrics(device_id, key, time_frame)}}
      end)
      |> assign(has_chart_data_key(key), false)
    end)
  end

  defp assign_metadata(%{assigns: %{device: device}} = socket) do
    metadata =
      if device.latest_health, do: device.latest_health.data["metadata"] || %{}, else: %{}

    assign(socket, :metadata, Map.drop(metadata, standard_keys(device)))
  end

  defp fetch_from_and_until(socket) do
    {unit, amount} = socket.assigns.time_frame

    from = DateTime.add(DateTime.utc_now(), -amount, String.to_existing_atom(unit))
    until = DateTime.utc_now()

    {from, until}
  end

  defp standard_keys(%{firmware_metadata: nil}), do: []

  defp standard_keys(%{firmware_metadata: firmware_metadata}),
    do: firmware_metadata |> Map.keys() |> Enum.map(&to_string/1)

  defp formatted_metrics(device_id, key, time_frame) do
    Metrics.get_device_metrics_by_key(device_id, key, time_frame)
    |> Enum.map(fn metric ->
      %{x: DateTime.to_unix(metric.inserted_at, :millisecond), y: metric.value}
    end)
  end

  defp chart_title(key) do
    String.replace(key, ~r/mb$/, "MB")
  end

  defp metrics_to_chart(latest_metrics) do
    latest_metrics
    |> Map.keys()
    |> Enum.reject(fn k ->
      k == "timestamp" or String.downcase(k) in @no_chart_metrics
    end)
    |> Enum.sort_by(fn key ->
      # Sorts list by @default_metrics order
      Enum.find_index(@default_metrics, fn {default_type, _} ->
        default_type == key
      end)
    end)
  end

  defp suggested_max(key) do
    cond do
      key == "cpu_temp" -> 100
      String.starts_with?(key, "load_") -> 1
      String.ends_with?(key, "_percent") or String.ends_with?(key, "_percentage") -> 100
      true -> nil
    end
  end

  defp title(type) do
    case Enum.find(@default_metrics, fn {default_type, _} -> default_type == type end) do
      {_, title} ->
        title

      nil ->
        type
        |> String.replace("_", " ")
        |> String.capitalize()
    end
    |> chart_title()
  end

  defp get_time_unit({"hour", _}), do: "minute"
  defp get_time_unit({"day", 1}), do: "hour"
  defp get_time_unit({"day", _}), do: "day"

  defp custom_metrics(metrics) do
    Enum.reject(metrics, &(elem(&1, 0) in @manual_metrics))
  end

  defp nice_round(val) when is_float(val), do: Float.round(val, 1)
  defp nice_round(val), do: val

  defp key_label(key) do
    key
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp chart_data_key(key), do: String.to_atom("#{key}_chart_data")
  defp has_chart_data_key(key), do: String.to_atom("#{key}_has_chart_data")

  defp validate_time_unit(unit) when unit in ~w(hour day minute second), do: unit
  defp validate_time_unit(_unit), do: elem(@default_time_frame, 0)
end

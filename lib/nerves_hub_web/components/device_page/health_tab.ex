defmodule NervesHubWeb.Components.DevicePage.HealthTab do
  use NervesHubWeb, tab_component: :health

  alias NervesHub.Devices.Metrics

  @time_frame_opts [
    {"hour", 1},
    {"day", 1},
    {"day", 7}
  ]
  @default_time_frame {"hour", 1}

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

  def tab_params(_params, _uri, socket) do
    time_frame = Map.get(socket.assigns, :time_frame, @default_time_frame)

    socket
    |> assign(:time_frame, time_frame)
    |> assign(:time_frame_opts, @time_frame_opts)
    |> assign(:latest_metrics, Metrics.get_latest_metric_set(socket.assigns.device.id))
    |> assign_charts()
    |> update_charts()
    |> cont()
  end

  def cleanup() do
    [:time_frame, :time_frame_opts, :charts]
  end

  def hooked_async(_name, _async_fun_result, socket), do: {:cont, socket}

  def hooked_event("set-time-frame", %{"unit" => unit, "amount" => amount}, socket) do
    payload = %{unit: get_time_unit({unit, String.to_integer(amount)})}

    socket
    |> assign(:time_frame, {unit, String.to_integer(amount)})
    |> push_event("update-time-unit", payload)
    |> update_charts()
    |> halt()
  end

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  def hooked_info(%Broadcast{event: "health_check_report"}, %{assigns: %{device: device}} = socket) do
    latest_metrics = Metrics.get_latest_metric_set(device.id)

    socket
    |> assign(:latest_metrics, latest_metrics)
    |> assign_metadata()
    |> update_charts()
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
      class="phx-click-loading:opacity-50 tab-content w-full p-6 opacity-0 transition-all duration-500"
    >
      <div :if={Enum.any?(@latest_metrics) && @health_enabled?} class="bg-base-900 border-base-700 mb-6 flex w-full flex-col rounded border">
        <div class="shadow-device-details-content flex flex-col">
          <div class="flex flex-wrap items-center justify-items-stretch gap-2 px-4 pt-2 pb-4">
            <div class="bg-health-good border-success flex h-16 grow flex-col rounded border-b px-3 py-2">
              <span class="text-base-400 text-xs tracking-wide">CPU</span>
              <div :if={@latest_metrics["cpu_usage_percent"] && @latest_metrics["cpu_temp"]} class="flex items-end justify-between">
                <span class="text-xl leading-[30px] text-neutral-50">{round(@latest_metrics["cpu_usage_percent"])}%</span>
                <span class="text-success text-base">{round(@latest_metrics["cpu_temp"])}°</span>
              </div>
              <div :if={@latest_metrics["cpu_usage_percent"] && !@latest_metrics["cpu_temp"]} class="flex items-end justify-between">
                <span class="text-xl leading-[30px] text-neutral-50">{round(@latest_metrics["cpu_usage_percent"])}%</span>
              </div>
              <div :if={!@latest_metrics["cpu_usage_percent"] && @latest_metrics["cpu_temp"]} class="flex items-end justify-between">
                <span class="text-xl leading-[30px] text-neutral-50">{round(@latest_metrics["cpu_temp"])}°</span>
              </div>
              <span :if={!@latest_metrics["cpu_usage_percent"] && !@latest_metrics["cpu_temp"]} class="text-nerves-gray-500 text-xl leading-[30px]">NA</span>
            </div>
            <div class="bg-health-warning border-warning flex h-16 grow flex-col rounded border-b px-3 py-2">
              <span class="text-base-400 text-xs tracking-wide">Memory used</span>
              <div :if={@latest_metrics["mem_used_mb"]} class="flex items-end justify-between">
                <span class="text-xl leading-[30px] text-neutral-50">{round(@latest_metrics["mem_used_mb"])}MB</span>
                <span class="text-warning text-base">{round(@latest_metrics["mem_used_percent"])}%</span>
              </div>
              <div :if={!@latest_metrics["mem_used_mb"]} class="flex items-end justify-between">
                <span class="text-nerves-gray-500 text-xl leading-[30px]">Not reported</span>
              </div>
            </div>
            <div class="bg-health-neutral flex h-16 grow flex-col rounded border-b border-indigo-500 px-3 py-2">
              <span class="text-base-400 text-xs tracking-wide">Load avg</span>
              <div :if={@latest_metrics["load_1min"] || @latest_metrics["load_5min"] || @latest_metrics["load_15min"]} class="flex items-center justify-between">
                <span :if={@latest_metrics["load_1min"]} class="text-xl leading-[30px] text-neutral-50">{@latest_metrics["load_1min"]}</span>
                <span :if={!@latest_metrics["load_1min"]} class="text-nerves-gray-500 text-xl leading-[30px]">NA</span>
                <span class="bg-base-700 h-4 w-px"></span>
                <span :if={@latest_metrics["load_5min"]} class="text-xl leading-[30px] text-neutral-50">{@latest_metrics["load_5min"]}</span>
                <span :if={!@latest_metrics["load_5min"]} class="text-nerves-gray-500 text-xl leading-[30px]">NA</span>
                <span class="bg-base-700 h-4 w-px"></span>
                <span :if={@latest_metrics["load_15min"]} class="text-xl leading-[30px] text-neutral-50">{@latest_metrics["load_15min"]}</span>
                <span :if={!@latest_metrics["load_15min"]} class="text-nerves-gray-500 text-xl leading-[30px]">NA</span>
              </div>
              <div :if={!@latest_metrics["load_1min"] && !@latest_metrics["load_5min"] && !@latest_metrics["load_15min"]} class="flex items-center">
                <span class="text-nerves-gray-500 text-xl leading-[30px]">Not reported</span>
              </div>
            </div>
            <div :for={{key, value} <- custom_metrics(@latest_metrics)} class="bg-health-plain flex h-16 grow flex-col rounded border-b border-neutral-500 px-3 py-2">
              <span class="text-xs tracking-wide text-neutral-400">{key_label(key)}</span>
              <span class="text-xl leading-[30px] text-neutral-50">{nice_round(value)}</span>
            </div>
          </div>
        </div>
      </div>

      <div class="bg-base-900 border-base-700 flex w-full flex-col rounded border">
        <div class="border-base-700 flex h-14 items-center justify-between border-b px-4">
          <div class="flex items-end gap-3">
            <div class="text-base font-medium text-neutral-50">Health over time</div>
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
                "border-base-600 hover:bg-base-700 hover:text-base-200 border px-4 py-2 text-sm font-medium first:rounded-s-lg last:rounded-e-lg focus:z-10 focus:ring-0",
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
          <div :if={Enum.empty?(@charts)} class="flex items-center justify-center p-6">
            <span class="text-base-500 font-extralight">No metrics for the selected period.</span>
          </div>

          <div :for={chart <- @charts} :if={Enum.any?(@charts)} class="flex flex-col gap-3">
            <div class="h-[200px] w-full">
              <canvas
                id={chart.type}
                phx-hook="Chart"
                phx-update="ignore"
                data-type={Jason.encode!(chart.type)}
                data-unit={Jason.encode!(chart.unit)}
                data-max={Jason.encode!(chart.max)}
                data-min={Jason.encode!(chart.min)}
                data-maxtime={Jason.encode!(chart.max_time)}
                data-mintime={Jason.encode!(chart.min_time)}
                data-metrics={Jason.encode!(chart.data)}
                data-title={Jason.encode!(chart_title(chart))}
              >
              </canvas>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp assign_charts(socket) do
    %{device: device, time_frame: time_frame, latest_metrics: latest_metrics} = socket.assigns

    charts = create_chart_data(device.id, time_frame, latest_metrics["mem_size_mb"])

    assign(socket, :charts, charts)
  end

  defp assign_metadata(%{assigns: %{device: device}} = socket) do
    metadata =
      if device.latest_health, do: device.latest_health.data["metadata"] || %{}, else: %{}

    assign(socket, :metadata, Map.drop(metadata, standard_keys(device)))
  end

  defp standard_keys(%{firmware_metadata: nil}), do: []

  defp standard_keys(%{firmware_metadata: firmware_metadata}),
    do: firmware_metadata |> Map.keys() |> Enum.map(&to_string/1)

  # @doc """
  # There are four cases for chart updates:
  #   - Create hooks if data previously was empty.
  #   - Clear hooks if there's no data for selected time frame.
  #   - Do a push_patch to render more or less charts if custom types varies for time frames.
  #   - Update existing hooks with new data via push_event (should happen most frequent).
  # """
  defp update_charts(%{charts: charts} = assigns) when charts == [], do: assign_charts(assigns)

  defp update_charts(
         %{
           assigns: %{
             device: device,
             product: product,
             org: org,
             time_frame: time_frame,
             latest_metrics: latest_metrics,
             charts: charts
           }
         } = socket
       ) do
    data = create_chart_data(device.id, time_frame, latest_metrics["size_mb"])

    cond do
      data == [] ->
        assign(socket, :charts, [])

      types(charts) != types(data) ->
        push_patch(socket,
          to: ~p"/org/#{org}/#{product}/devices/#{device}/health"
        )

      true ->
        Enum.reduce(data, socket, fn %{type: type, data: data}, socket ->
          type = if is_binary(type), do: type, else: Atom.to_string(type)
          push_event(socket, "update-charts", %{type: type, data: data})
        end)
    end
  end

  defp types(data) do
    Enum.map(data, &Map.get(&1, :type))
  end

  defp create_chart_data(device_id, {unit, _} = time_frame, memory_size) do
    metrics =
      device_id
      |> Metrics.get_device_metrics(time_frame)

    %{inserted_at: max_time} =
      Enum.max_by(metrics, & &1.inserted_at, DateTime, fn ->
        %{inserted_at: DateTime.from_unix!(0)}
      end)

    %{inserted_at: min_time} =
      Enum.min_by(metrics, & &1.inserted_at, DateTime, fn ->
        %{inserted_at: DateTime.from_unix!(1)}
      end)

    metrics
    |> Enum.group_by(& &1.key)
    |> filter_and_sort()
    |> Enum.map(fn {type, metrics} ->
      data = organize_metrics_for_chart(metrics, unit)

      # Build structure for rendering charts
      %{
        type: type,
        title: title(type),
        data: data,
        max: get_max_value(type, data, memory_size),
        min: get_min_value(type, data),
        min_time: min_time,
        max_time: max_time,
        unit: get_time_unit(time_frame)
      }
    end)
  end

  defp filter_and_sort(metrics) do
    metrics
    |> Enum.reject(fn {type, _} -> type in @no_chart_metrics end)
    |> Enum.sort_by(fn {type, _} ->
      # Sorts list by @default_metrics order
      Enum.find_index(@default_metrics, fn {default_type, _} ->
        default_type == type
      end)
    end)
  end

  defp organize_metrics_for_chart(metrics, unit) do
    metrics
    |> get_max_per_hour(unit)
    |> Enum.map(fn %{inserted_at: timestamp, value: value} ->
      %{x: DateTime.to_string(timestamp), y: value}
    end)
  end

  defp chart_title(chart) do
    String.replace(chart.title, ~r/mb$/, "MB")
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
  end

  # Do nothing if time frame unit is hour
  defp get_max_per_hour(metrics, "hour"), do: metrics

  defp get_max_per_hour(metrics, _unit) do
    metrics
    |> Enum.group_by(& &1.inserted_at.hour)
    |> Enum.map(fn {_key, val} ->
      Enum.max_by(val, & &1.value)
    end)
    |> Enum.sort_by(& &1.inserted_at)
  end

  defp get_time_unit({"hour", _}), do: "minute"
  defp get_time_unit({"day", 1}), do: "hour"
  defp get_time_unit({"day", _}), do: "day"

  defp get_max_value(_type, data, _memory_size) when data == [], do: 0

  defp get_max_value(type, data, memory_size) do
    case type do
      "load_" <> _ ->
        cpu_load_max_value(data)

      "mem_used_mb" ->
        memory_size

      type
      when type in ["mem_used_percent", "cpu_temp", "cpu_usage_percent", "disk_used_percentage"] ->
        100

      _ ->
        data
        |> Enum.max_by(& &1.y)
        |> Map.get(:y)
        # Space it out a little
        |> Kernel.+(1.0)
    end
  end

  defp cpu_load_max_value(data) do
    data
    |> Enum.max_by(& &1.y)
    |> Map.get(:y)
    |> ceil()
    |> max(1)
  end

  defp get_min_value(type, data) do
    case type do
      "load_" <> _ ->
        0

      type
      when type in [
             "mem_used_mb",
             "mem_used_percent",
             "cpu_temp",
             "cpu_usage_percent",
             "disk_used_percentage"
           ] ->
        0

      _ ->
        data
        |> Enum.min_by(& &1.y)
        |> Map.get(:y)
        # Space it out a little
        |> Kernel.-(1.0)
    end
  end

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
end

defmodule NervesHubWeb.Components.DevicePage.HealthTab do
  use NervesHubWeb, tab_component: :health

  alias NervesHub.Devices
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
    socket
    |> assign(:time_frame, @default_time_frame)
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

    socket =
      socket
      |> assign(:time_frame, {unit, String.to_integer(amount)})
      |> push_event("update-time-unit", payload)
      |> update_charts()

    {:halt, socket}
  end

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  def hooked_info(
        %Broadcast{event: "health_check_report"},
        %{assigns: %{device: device}} = socket
      ) do
    latest_metrics = Metrics.get_latest_metric_set(device.id)

    socket =
      socket
      |> assign(:latest_metrics, latest_metrics)
      |> assign_metadata()

    {:halt, socket}
  end

  def hooked_info(_event, socket), do: {:cont, socket}

  def render(assigns) do
    ~H"""
    <div class="w-full p-6">
      <div :if={Enum.any?(@latest_metrics) && @health_enabled?} class="w-full flex flex-col bg-zinc-900 border border-zinc-700 rounded">
        <div class="flex flex-col shadow-device-details-content">
          <div class="flex pt-2 px-4 pb-4 gap-2 items-center justify-items-stretch flex-wrap">
            <div class="grow flex flex-col h-16 py-2 px-3 rounded border-b border-emerald-500 bg-health-good">
              <span class="text-xs text-zinc-400 tracking-wide">CPU</span>
              <div :if={@latest_metrics["cpu_usage_percent"] && @latest_metrics["cpu_temp"]} class="flex justify-between items-end">
                <span class="text-xl leading-[30px] text-neutral-50">{round(@latest_metrics["cpu_usage_percent"])}%</span>
                <span class="text-base text-emerald-500">{round(@latest_metrics["cpu_temp"])}°</span>
              </div>
              <div :if={@latest_metrics["cpu_usage_percent"] && !@latest_metrics["cpu_temp"]} class="flex justify-between items-end">
                <span class="text-xl leading-[30px] text-neutral-50">{round(@latest_metrics["cpu_usage_percent"])}%</span>
              </div>
              <div :if={!@latest_metrics["cpu_usage_percent"] && @latest_metrics["cpu_temp"]} class="flex justify-between items-end">
                <span class="text-xl leading-[30px] text-neutral-50">{round(@latest_metrics["cpu_temp"])}°</span>
              </div>
              <span :if={!@latest_metrics["cpu_usage_percent"] && !@latest_metrics["cpu_temp"]} class="text-xl leading-[30px] text-nerves-gray-500">NA</span>
            </div>
            <div class="grow flex flex-col h-16 py-2 px-3 rounded border-b border-amber-500 bg-health-warning">
              <span class="text-xs text-zinc-400 tracking-wide">Memory used</span>
              <div :if={@latest_metrics["mem_used_mb"]} class="flex justify-between items-end">
                <span class="text-xl leading-[30px] text-neutral-50">{round(@latest_metrics["mem_used_mb"])}MB</span>
                <span class="text-base text-amber-500">{round(@latest_metrics["mem_used_percent"])}%</span>
              </div>
              <div :if={!@latest_metrics["mem_used_mb"]} class="flex justify-between items-end">
                <span class="text-xl leading-[30px] text-nerves-gray-500">Not reported</span>
              </div>
            </div>
            <div class="grow flex flex-col h-16 py-2 px-3 rounded border-b border-indigo-500 bg-health-neutral">
              <span class="text-xs text-zinc-400 tracking-wide">Load avg</span>
              <div :if={@latest_metrics["load_1min"] || @latest_metrics["load_5min"] || @latest_metrics["load_15min"]} class="flex justify-between items-center">
                <span :if={@latest_metrics["load_1min"]} class="text-xl leading-[30px] text-neutral-50">{@latest_metrics["load_1min"]}</span>
                <span :if={!@latest_metrics["load_1min"]} class="text-xl leading-[30px] text-nerves-gray-500">NA</span>
                <span class="w-px h-4 bg-zinc-700"></span>
                <span :if={@latest_metrics["load_5min"]} class="text-xl leading-[30px] text-neutral-50">{@latest_metrics["load_5min"]}</span>
                <span :if={!@latest_metrics["load_5min"]} class="text-xl leading-[30px] text-nerves-gray-500">NA</span>
                <span class="w-px h-4 bg-zinc-700"></span>
                <span :if={@latest_metrics["load_15min"]} class="text-xl leading-[30px] text-neutral-50">{@latest_metrics["load_15min"]}</span>
                <span :if={!@latest_metrics["load_15min"]} class="text-xl leading-[30px] text-nerves-gray-500">NA</span>
              </div>
              <div :if={!@latest_metrics["load_1min"] && !@latest_metrics["load_5min"] && !@latest_metrics["load_15min"]} class="flex items-center">
                <span class="text-xl leading-[30px] text-nerves-gray-500">Not reported</span>
              </div>
            </div>
            <div :for={{key, value} <- custom_metrics(@latest_metrics)} class="grow flex flex-col h-16 py-2 px-3 rounded border-b border-neutral-500 bg-health-plain">
              <span class="text-xs text-neutral-400 tracking-wide">{key_label(key)}</span>
              <span class="text-xl leading-[30px] text-neutral-50">{nice_round(value)}</span>
            </div>
          </div>
        </div>
      </div>

      <div class="my-6 w-full flex flex-col bg-zinc-900 border border-zinc-700 rounded">
        <div class="flex justify-between items-center h-14 px-4 border-b border-zinc-700">
          <div class="flex items-end gap-3">
            <div class="text-base text-neutral-50 font-medium">Health over time</div>
            <div :if={@latest_metrics["timestamp"]} class="text-xs text-nerves-gray-500 tracking-wide mr-auto">
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
                "px-4 py-2 text-sm font-medium border border-base-600 first:rounded-s-lg last:rounded-e-lg hover:text-zinc-200 hover:bg-zinc-700 focus:z-10 focus:ring-0",
                {unit, amount} != @time_frame && "text-zinc-300 bg-zinc-800",
                {unit, amount} == @time_frame && "text-zinc-200 bg-zinc-700"
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

        <div class="p-10 flex flex-col gap-10">
          <div :if={Enum.empty?(@charts)} class="flex items-center justify-center p-6">
            <span class="text-indigo-500 font-extralight">No data for selected period.</span>
          </div>

          <div :for={chart <- @charts} :if={Enum.any?(@charts)} class="flex flex-col gap-3">
            <div class="w-full h-[200px]">
              <canvas
                id={chart.type}
                phx-hook="Chart"
                phx-update="ignore"
                data-type={Jason.encode!(chart.type)}
                data-unit={Jason.encode!(chart.unit)}
                data-max={Jason.encode!(chart.max)}
                data-min={Jason.encode!(chart.min)}
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
    health = Devices.get_latest_health(device.id)

    metadata =
      if health, do: health.data["metadata"] || %{}, else: %{}

    assign(socket, :metadata, Map.drop(metadata, standard_keys(device)))
  end

  defp standard_keys(%{firmware_metadata: nil}), do: []

  defp standard_keys(%{firmware_metadata: firmware_metadata}),
    do:
      firmware_metadata
      |> Map.keys()
      |> Enum.map(&to_string/1)

  # @doc """
  # There are four cases for chart updates:
  #   - Create hooks if data previously was empty.
  #   - Clear hooks if there's no data for selected time frame.
  #   - Do a push_patch to render more or less charts if custom types varies for time frames.
  #   - Update existing hooks with new data via push_event (should happen most frequent).
  # """
  defp update_charts(%{charts: charts} = assigns) when charts == [],
    do: assign_charts(assigns)

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
         } =
           socket
       ) do
    data = create_chart_data(device.id, time_frame, latest_metrics["size_mb"])

    cond do
      data == [] ->
        assign(socket, :charts, [])

      types(charts) != types(data) ->
        push_patch(socket,
          to: ~p"/org/#{org.name}/#{product.name}/devices/#{device.identifier}/healthz"
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
    device_id
    |> Metrics.get_device_metrics(time_frame)
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
        min: get_min_value(data),
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
    end
  end

  defp cpu_load_max_value(data) do
    data
    |> Enum.max_by(& &1.y)
    |> Map.get(:y)
    |> ceil()
    |> max(1)
  end

  defp get_min_value(data) do
    data
    |> Enum.min_by(& &1.y)
    |> Map.get(:y)
  end

  defp custom_metrics(metrics) do
    metrics
    |> Enum.reject(fn {key, _value} ->
      key in @manual_metrics
    end)
  end

  defp nice_round(val) when is_float(val), do: Float.round(val, 1)
  defp nice_round(val), do: val

  defp key_label(key) do
    key
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end

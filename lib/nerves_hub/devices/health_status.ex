defmodule NervesHub.Devices.HealthStatus do
  alias NervesHub.Devices.Metrics
  alias NervesHub.Devices.Device

  @type health_status() ::
          :unknown
          | :healthy
          | {:warning, %{}}
          | {:unhealthy, %{}}

  @empty_report %{warning: [], unhealthy: []}
  @default_thresholds %{
    "cpu_usage_percent" => %{unhealthy: 90, warning: 80},
    "mem_used_percent" => %{unhealthy: 80, warning: 70},
    "disk_used_percentage" => %{unhealthy: 90, warning: 80}
  }

  def default_thresholds(), do: @default_thresholds

  @doc """
  Calculates health status from map of metrics.

  Returns `:status` or `{:status, reasons}`
  """
  @spec calculate_metrics_status(map()) :: health_status()
  def calculate_metrics_status(metrics_map) do
    metrics_map
    |> Enum.reduce({:unknown, @empty_report}, fn metric, {current_status, report} ->
      {key, _value} = metric

      case metrics_status(metric) do
        :unhealthy ->
          {:unhealthy, Map.put(report, :unhealthy, [key | report.unhealthy])}

        :warning ->
          {status(current_status, :warning), Map.put(report, :warning, [key | report.warning])}

        :healthy ->
          {status(current_status, :healthy), report}

        :unknown ->
          {current_status, report}
      end
    end)
    |> report_status()
  end

  @spec latest_metrics_status(Device.t()) :: health_status()
  def latest_metrics_status(device) do
    device.id
    |> Metrics.get_latest_metric_set()
    |> calculate_metrics_status()
  end

  defp metrics_status({key, value}) do
    if key in Map.keys(@default_thresholds) do
      %{unhealthy: max, warning: warning} = Map.get(@default_thresholds, key)

      cond do
        value >= max -> :unhealthy
        value >= warning -> :warning
        true -> :healthy
      end
    else
      :unknown
    end
  end

  defp report_status({status, @empty_report}), do: status
  defp report_status(status), do: status

  defp status(:unhealthy, _), do: :unhealthy
  defp status(:warning, _new_status), do: :warning
  defp status(_current_status, :warning), do: :warning
  defp status(_current_status, :healthy), do: :healthy
  defp status(current_status, _), do: current_status
end

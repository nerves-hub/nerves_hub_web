defmodule NervesHub.Devices.HealthStatus do
  @type health_status() ::
          :unknown
          | :healthy
          | {:warning, %{}}
          | {:unhealthy, %{}}

  @empty_report %{warning: %{}, unhealthy: %{}}
  @default_thresholds %{
    "cpu_usage_percent" => %{unhealthy: 90, warning: 80},
    "mem_used_percent" => %{unhealthy: 80, warning: 70},
    "disk_used_percentage" => %{unhealthy: 90, warning: 80}
  }

  def default_thresholds(), do: @default_thresholds

  @doc """
  Calculates health status from map of metrics.

  Accepts a map of thresholds, or uses defaults from module attribute.

  Returns `:status` or `{:status, reasons}`
  """
  @spec calculate_metrics_status(map(), map()) :: health_status()
  def calculate_metrics_status(metrics_map, thresholds \\ @default_thresholds) do
    metrics_map
    |> Enum.reduce({:unknown, @empty_report}, fn metric, {current_status, reasons} ->
      {key, value} = metric

      case metrics_status(metric, thresholds) do
        :unhealthy ->
          reason = %{value: value, threshold: thresholds[key].unhealthy}
          unhealthy_reasons = Map.put(reasons.unhealthy, key, reason)

          {:unhealthy, %{reasons | unhealthy: unhealthy_reasons}}

        :warning ->
          reason = %{value: value, threshold: thresholds[key].warning}
          warning_reasons = Map.put(reasons.warning, key, reason)

          {status(current_status, :warning), %{reasons | warning: warning_reasons}}

        :healthy ->
          {status(current_status, :healthy), reasons}

        :unknown ->
          {current_status, reasons}
      end
    end)
    |> report_status()
  end

  defp metrics_status({key, value}, thresholds) do
    if key in Map.keys(thresholds) do
      %{unhealthy: max, warning: warning} = Map.get(thresholds, key)

      cond do
        value >= max -> :unhealthy
        value >= warning -> :warning
        true -> :healthy
      end
    else
      :unknown
    end
  end

  defp report_status({status, _reasons}) when status in [:unknown, :healthy], do: status
  defp report_status(status), do: status

  defp status(:unhealthy, _), do: :unhealthy
  defp status(:warning, _new_status), do: :warning
  defp status(_current_status, :warning), do: :warning
  defp status(_current_status, :healthy), do: :healthy
  defp status(current_status, _), do: current_status
end

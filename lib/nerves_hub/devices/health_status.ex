defmodule NervesHub.Devices.HealthStatus do
  alias NervesHub.Devices.Metrics
  alias NervesHub.Devices.Device

  @type health_status() ::
          :unknown
          | :healthy
          | :warning
          | :unhealthy

  @default_thresholds %{
    "cpu_usage_percent" => %{unhealthy: 90, warning: 80},
    "mem_used_percent" => %{unhealthy: 80, warning: 70},
    "disk_used_percentage" => %{unhealthy: 90, warning: 80}
  }

  def default_thresholds(), do: @default_thresholds

  @spec latest_metrics_status(Device.t()) :: health_status()
  def latest_metrics_status(device) do
    device.id
    |> Metrics.get_latest_metric_set()
    |> Enum.reduce_while(:unknown, fn metric, current_status ->
      case metrics_status(metric) do
        :unhealthy -> {:halt, :unhealthy}
        :warning -> {:cont, :warning}
        new_status -> {:cont, status(current_status, new_status)}
      end
    end)
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

  defp status(:warning, _new_status), do: :warning
  defp status(_current_status, :healthy), do: :healthy
  defp status(current_status, _), do: current_status
end

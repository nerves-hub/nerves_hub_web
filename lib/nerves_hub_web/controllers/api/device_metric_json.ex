defmodule NervesHubWeb.API.DeviceMetricJSON do
  @moduledoc false

  def index(%{reports: reports}) do
    %{data: for(report <- reports, do: report(report))}
  end

  defp report(report) do
    %{
      timestamp: report.timestamp,
      # The firmware the device was running when it took the readings, so a
      # metric can be compared across releases.
      firmware_uuid: report.firmware_uuid,
      metrics: report.metrics
    }
  end
end

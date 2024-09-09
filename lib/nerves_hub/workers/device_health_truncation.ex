defmodule NervesHub.Workers.DeviceHealthTruncation do
  @moduledoc """
  Remove old Device health and metric reports.

  The number of days to keep is configured using the environment
  variable `HEALTH_CHECK_DAYS_TO_RETAIN`
  """

  use Oban.Worker,
    max_attempts: 1,
    queue: :truncate

  @impl Oban.Worker
  def perform(_) do
    {:ok, _} = NervesHub.Devices.truncate_device_health()
    {:ok, _} = NervesHub.Devices.Metrics.truncate_device_metrics()

    :ok
  end
end

defmodule NervesHub.Workers.DeviceHealthTruncation do
  @moduledoc """
  Remove old Device health and metric reports.

  The number of days to keep is configured using the environment
  variable `HEALTH_CHECK_DAYS_TO_RETAIN`.

  Metrics live in ClickHouse now and expire on that table's own TTL. The metrics
  call here drains what is left in the retired PostgreSQL table so it is empty
  by the time it is dropped, and goes with it.
  """

  use Oban.Worker,
    queue: :cleanup,
    max_attempts: 1

  alias NervesHub.Devices.Health
  alias NervesHub.Devices.Metrics

  @impl Oban.Worker
  def perform(_) do
    :ok = Health.truncate_device_health()
    {:ok, _} = Metrics.truncate_device_metrics()

    :ok
  end
end

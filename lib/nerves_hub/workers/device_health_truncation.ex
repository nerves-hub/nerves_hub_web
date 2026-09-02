defmodule NervesHub.Workers.DeviceHealthTruncation do
  @moduledoc """
  Remove old Device health reports.

  The number of days to keep is configured using the environment
  variable `HEALTH_CHECK_DAYS_TO_RETAIN`.

  Metrics used to be truncated here too. They live in ClickHouse now and expire
  on that table's own TTL, which needs no worker.
  """

  use Oban.Worker,
    queue: :cleanup,
    max_attempts: 1

  alias NervesHub.Devices.Health

  @impl Oban.Worker
  def perform(_) do
    :ok = Health.truncate_device_health()
  end
end

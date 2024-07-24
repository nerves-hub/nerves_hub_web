defmodule NervesHub.Workers.DeviceHealthTruncation do
  @moduledoc """
  Remove old Device health reports.

  The number of days to keep is configured using the environment
  variable `HEALTH_CHECK_DAYS_TO_RETAIN`
  """

  use Oban.Worker,
    max_attempts: 1,
    queue: :truncate

  @impl true
  def perform(_) do
    {:ok, _} = NervesHub.Devices.truncate_device_health()

    :ok
  end
end

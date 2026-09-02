defmodule Mix.Tasks.NervesHub.Gen.Metrics do
  @shortdoc "Generate metrics for one or more devices"

  @moduledoc """
  Generate a week of metrics for a device, one report every twenty minutes.

  Goes through `NervesHub.Devices.Metrics.record/3`, so it fills ClickHouse and
  the device's latest set exactly as a real report would. Needs a ClickHouse to
  write the history to; without one only the latest set is filled in.

  ## Examples

      mix nerves_hub.gen.metrics device-1234
  """

  use Mix.Task

  alias NervesHub.Analytics.Buffer
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceMetric
  alias NervesHub.Devices.Metrics
  alias NervesHub.Repo

  @requirements ["app.start"]
  @preferred_cli_env :dev

  @impl Mix.Task
  def run([device_identifier | _]) do
    device = Repo.get_by!(Device, identifier: device_identifier)

    device_info = %DeviceInfo{
      device_id: device.id,
      device_identifier: device.identifier,
      org_id: device.org_id,
      product_id: device.product_id
    }

    now = DateTime.truncate(DateTime.utc_now(), :millisecond)
    a_week_ago = DateTime.add(now, -7, :day)

    :ok = add_metrics(device_info, now, a_week_ago)

    # Reports are buffered, so without this the task can exit before ClickHouse
    # has seen the last batch.
    :ok = Buffer.flush(DeviceMetric)
  end

  # Walks backwards from `timestamp` until it passes `stop_at`. Newest first,
  # which is also what leaves the newest report as the device's latest set --
  # the upsert behind `record/3` refuses to move it backwards.
  defp add_metrics(device_info, timestamp, stop_at) when timestamp <= stop_at do
    save_metrics(device_info, timestamp)
  end

  defp add_metrics(device_info, timestamp, stop_at) do
    :ok = save_metrics(device_info, timestamp)

    add_metrics(device_info, DateTime.add(timestamp, -20, :minute), stop_at)
  end

  defp save_metrics(device_info, timestamp) do
    metrics = %{
      "cpu_temp" => Enum.random(1..100),
      "load_1min" => Float.ceil(:rand.uniform(), 2),
      "load_5min" => Float.ceil(:rand.uniform(), 2),
      "load_15min" => Float.ceil(:rand.uniform(), 2),
      "mem_size_mb" => 7892,
      "mem_used_mb" => Enum.random(0..7892),
      "mem_used_percent" => Enum.random(0..100)
    }

    {:ok, _stored} = Metrics.record(device_info, metrics, timestamp)

    :ok
  end
end

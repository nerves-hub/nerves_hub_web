defmodule NervesHub.Devices.Metrics do
  import Ecto.Query

  alias NervesHub.Devices.DeviceMetric
  alias NervesHub.Repo

  @default_metrics [
    "cpu_temp",
    "cpu_usage_percent",
    "load_15min",
    "load_1min",
    "load_5min",
    "size_mb",
    "used_mb",
    "used_percent"
  ]

  def default_metrics, do: @default_metrics

  @doc """
  Get all metrics for device
  """
  def get_device_metrics(device_id) do
    DeviceMetric
    |> where(device_id: ^device_id)
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Get metrics by device within a specified time frame
  """
  def get_device_metrics(device_id, {time_unit, amount}) do
    DeviceMetric
    |> where(device_id: ^device_id)
    |> where([d], d.inserted_at > ago(^amount, ^time_unit))
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Get specific key metrics for device
  """
  def get_device_metrics_by_key(device_id, key) do
    DeviceMetric
    |> where(device_id: ^device_id)
    |> where(key: ^key)
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Get specific key metrics for device within a specified time frame
  """
  def get_device_metrics_by_key(device_id, key, {time_unit, amount}) do
    DeviceMetric
    |> where(device_id: ^device_id)
    |> where(key: ^key)
    |> where([d], d.inserted_at > ago(^amount, ^time_unit))
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  def get_product_metrics_by_key(product_id, key) do
    DeviceMetric
    |> join(:left, [dm], d in assoc(dm, :device))
    |> where([_, d], d.product_id == ^product_id)
    |> where([dm, _], dm.key == ^key)
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  def get_product_metrics_by_key(product_id, key, time_unit, amount) do
    DeviceMetric
    |> join(:left, [dm], d in assoc(dm, :device))
    |> where([_, d], d.product_id == ^product_id)
    |> where([dm, _], dm.key == ^key)
    |> where([d], d.inserted_at > ago(^amount, ^time_unit))
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  def get_latest_metric(device_id) do
    DeviceMetric
    |> where(device_id: ^device_id)
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  def get_latest_metric(device_id, key) do
    DeviceMetric
    |> where(device_id: ^device_id)
    |> where(key: ^key)
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  def get_latest_timestamp_for_device(device_id) do
    device_id
    |> get_latest_metric()
    |> case do
      %DeviceMetric{inserted_at: timestamp} -> timestamp
      _ -> nil
    end
  end

  @doc """
  Retrieves the latest metric set, together with the timestamp, for a given device.

  Uses a subquery to filter the `DeviceMetric` table on the most recent `inserted_at` timestamp.
  """
  def get_latest_metric_set(device_id) do
    DeviceMetric
    |> where([dm], dm.device_id == ^device_id)
    |> where(
      [dm],
      dm.inserted_at ==
        subquery(
          DeviceMetric
          |> select([:inserted_at])
          |> where(device_id: ^device_id)
          |> order_by(desc: :inserted_at)
          |> limit(1)
        )
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn item, acc ->
      acc
      |> Map.put(item.key, item.value)
      |> Map.put_new("timestamp", item.inserted_at)
    end)
  end

  @doc """
  Saves single metric.
  """
  def save_metric(params) do
    params
    |> DeviceMetric.save()
    |> Repo.insert()
  end

  @doc """
  Saves map of metrics.
  """
  def save_metrics(device_id, metrics) do
    entries =
      Enum.map(metrics, fn {key, val} ->
        DeviceMetric.save(%{device_id: device_id, key: key, value: val}).changes
        |> Map.merge(%{inserted_at: {:placeholder, :now}})
      end)

    results = Repo.insert_all(DeviceMetric, entries, placeholders: %{now: DateTime.utc_now()})

    case results do
      {0, _} -> :error
      {count, _} -> {:ok, count}
    end
  end

  @doc """
  Delete metrics after x days
  """
  def truncate_device_metrics() do
    days_to_retain =
      Application.get_env(:nerves_hub, :device_health_days_to_retain)

    days_ago = DateTime.shift(DateTime.utc_now(), day: -days_to_retain)

    {count, _} =
      DeviceMetric
      |> where([dh], dh.inserted_at < ^days_ago)
      |> Repo.delete_all()

    {:ok, count}
  end
end

defmodule NervesHub.Devices.Metrics do
  import Ecto.Query

  alias NervesHub.Devices.DeviceMetric
  alias NervesHub.Repo

  @default_metric_types [
    :cpu_temp,
    :load_15min,
    :load_1min,
    :load_5min,
    :size_mb,
    :used_mb,
    :used_percent
  ]

  def default_metric_types, do: @default_metric_types

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
  def get_device_metrics(device_id, time_unit, amount) do
    DeviceMetrics
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

  def get_custom_metrics_for_device(device_id) do
    default_metrics = Enum.map(@default_metric_types, &Atom.to_string/1)

    DeviceMetric
    |> where(device_id: ^device_id)
    |> where([dm], dm.key not in ^default_metrics)
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  def get_custom_metrics_for_device(device_id, {time_unit, amount}) do
    default_metrics = Enum.map(@default_metric_types, &Atom.to_string/1)

    DeviceMetric
    |> where(device_id: ^device_id)
    |> where([dm], dm.key not in ^default_metrics)
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

  def get_latest_value(device_id, key) do
    device_id
    |> get_latest_metric(key)
    |> get_value_or_nil()
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
  Get map with latest values for all metric types. Also includes timestamp.
  """
  def get_latest_metric_set_for_device(device_id) do
    @default_metric_types
    |> Enum.reduce(%{}, fn type, acc ->
      Map.put(acc, type, get_latest_value(device_id, Atom.to_string(type)))
    end)
    |> Map.put(:timestamp, get_latest_timestamp_for_device(device_id))
  end

  defp get_value_or_nil(%DeviceMetric{value: value}), do: value
  defp get_value_or_nil(_), do: nil

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
    Repo.transaction(fn ->
      Enum.map(metrics, fn {key, val} ->
        save_metric(%{device_id: device_id, key: key, value: val})
      end)
    end)
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

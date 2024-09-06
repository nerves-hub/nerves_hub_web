defmodule NervesHub.Devices.Metrics do
  import Ecto.Query

  alias NervesHub.Devices.DeviceMetric
  alias NervesHub.Repo

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
  def get_device_metrics_by_key(device_id, key, time_unit, amount) do
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

  def save_metric(params) do
    params
    |> DeviceMetric.save()
    |> Repo.insert()
  end

  def save_metrics(device_id, metrics) do
    Repo.transaction(fn ->
      Enum.map(metrics, fn {key, val} ->
        save_metric(%{device_id: device_id, key: key, value: val})
      end)
    end)
  end

  def truncate_device_metrics() do
    days_to_retain =
      Application.get_env(:nerves_hub, :device_health_days_to_retain)

    days_ago = DateTime.shift(DateTime.utc_now(), day: -days_to_retain)

    {count, _} =
      DeviceMetrics
      |> where([dh], dh.inserted_at < ^days_ago)
      |> Repo.delete_all()

    {:ok, count}
  end
end

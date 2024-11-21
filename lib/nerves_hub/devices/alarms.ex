defmodule NervesHub.Devices.Alarms do
  import Ecto.Query
  alias NervesHub.Repo
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceHealth

  @doc """
  Selects device id:s for devices that has alarm(s) in it's latest health record.
  Used when filtering devices.
  """
  def query_devices_with_alarms() do
    (lr in subquery(latest_row_query()))
    |> from()
    |> where([lr], lr.rn == 1)
    |> where([lr], fragment("?->'alarms' != '{}'", lr.data))
    |> join(:inner, [lr], d in Device, on: lr.device_id == d.id)
    |> select([lr, o], o.id)
  end

  @doc """
  Selects device id:s for devices that has provided alarm in it's latest health record.
  Used when filtering devices.
  """
  def query_devices_with_alarm(alarm) do
    (lr in subquery(latest_row_query()))
    |> from()
    |> where([lr], lr.rn == 1)
    |> where(
      [lr],
      fragment(
        "EXISTS (SELECT 1 FROM jsonb_each_text(?) WHERE value ILIKE ?)",
        lr.data,
        ^"%#{alarm}%"
      )
    )
    |> join(:inner, [lr], d in Device, on: lr.device_id == d.id)
    |> select([lr, o], o.id)
  end

  @doc """
  Creates a list with all current alarm types for a product.
  """
  def get_current_alarm_types(product_id) do
    query_current_alarms(product_id)
    |> Repo.all()
    |> Enum.map(fn %{data: data} ->
      Map.keys(data["alarms"])
    end)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.map(&String.trim_leading(&1, "Elixir."))
  end

  @doc """
  Counts number of devices currently alarming, within a product.
  """
  def current_alarms_count(product_id) do
    product_id
    |> query_current_alarms()
    |> select([a], count(a))
    |> Repo.one!()
  end

  def get_current_alarms_for_device(device) do
    device.id
    |> Devices.get_latest_health()
    |> case do
      %DeviceHealth{data: %{"alarms" => alarms}} when is_map(alarms) ->
        for {alarm, description} <- alarms,
            do: {String.trim_leading(alarm, "Elixir."), description}

      _ ->
        nil
    end
  end

  @doc """
  Selects latest health per device if alarms is populated and device belongs to product.
  """
  def query_current_alarms(product_id) do
    (lr in subquery(latest_row_query()))
    |> from()
    |> where([lr], lr.rn == 1)
    |> where([lr], fragment("?->'alarms' != '{}'", lr.data))
    |> where([lr], lr.device_id in subquery(device_product_query(product_id)))
  end

  defp latest_row_query() do
    DeviceHealth
    |> select([dh], %{
      device_id: dh.device_id,
      data: dh.data,
      inserted_at: dh.inserted_at,
      rn: row_number() |> over(partition_by: dh.device_id, order_by: [desc: dh.inserted_at])
    })
  end

  defp device_product_query(product_id) do
    Device
    |> select([:id])
    |> where(product_id: ^product_id)
  end
end

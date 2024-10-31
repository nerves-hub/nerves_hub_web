defmodule NervesHub.Devices.Alarms do
  import Ecto.Query
  alias NervesHub.Repo
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceHealth

  @doc """
  Selects device id:s for devices that has alarm(s) in it's latest health record.
  Used when filtering devices
  """
  def query_devices_with_alarms do
    from(
      lr in subquery(
        from(dh in DeviceHealth,
          where: fragment("?->'alarms' != '{}'", dh.data),
          select: %{
            device_id: dh.device_id,
            inserted_at: dh.inserted_at,
            rn: row_number() |> over(partition_by: dh.device_id, order_by: [desc: dh.inserted_at])
          }
        )
      ),
      where: lr.rn == 1
    )
    |> join(:inner, [lr], d in Device, on: lr.device_id == d.id)
    |> select([lr, o], o.id)
  end

  def query_devices_with_alarm(alarm) do
    from(
      lr in subquery(
        from(dh in DeviceHealth,
          where:
            fragment(
              "EXISTS (SELECT 1 FROM jsonb_each_text(?) WHERE value ILIKE ?)",
              dh.data,
              ^"%#{alarm}%"
            ),
          select: %{
            device_id: dh.device_id,
            inserted_at: dh.inserted_at,
            rn: row_number() |> over(partition_by: dh.device_id, order_by: [desc: dh.inserted_at])
          }
        )
      ),
      where: lr.rn == 1
    )
    |> join(:inner, [lr], d in Device, on: lr.device_id == d.id)
    |> select([lr, o], o.id)
  end

  def get_current_alarms() do
    from(
      lr in subquery(
        from(dh in DeviceHealth,
          where: fragment("?->'alarms' != '{}'", dh.data),
          select: %{
            device_id: dh.device_id,
            data: dh.data,
            inserted_at: dh.inserted_at,
            rn: row_number() |> over(partition_by: dh.device_id, order_by: [desc: dh.inserted_at])
          }
        )
      ),
      where: lr.rn == 1
    )
    |> Repo.all()
    |> Enum.map(fn %{data: data} ->
      Map.keys(data["alarms"])
    end)
    |> List.flatten()
    |> Enum.uniq()
  end
end

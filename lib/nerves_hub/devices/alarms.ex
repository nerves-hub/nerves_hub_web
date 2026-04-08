defmodule NervesHub.Devices.Alarms do
  import Ecto.Query

  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceHealth
  alias NervesHub.Repo

  @doc """
  Creates a list with all current alarm types for a product.
  """
  def get_current_alarm_types(product_id) do
    devices_with_alarms_query(product_id)
    |> select([latest_health: lh], %{alarms: lh.data["alarms"]})
    |> Repo.all()
    |> Enum.map(fn %{alarms: alarms} ->
      Map.keys(alarms)
    end)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.map(&String.trim_leading(&1, "Elixir."))
  end

  @doc """
  Counts number of devices currently alarming, within a product.
  """
  def current_alarms_count(product_id) do
    devices_with_alarms_query(product_id)
    |> Repo.aggregate(:count)
  end

  def current_alarms_for_device(device) do
    case device.latest_health do
      %DeviceHealth{data: %{"alarms" => alarms}} when is_map(alarms) and map_size(alarms) > 0 ->
        for {alarm, description} <- alarms,
            do: {String.trim_leading(alarm, "Elixir."), description}

      _ ->
        nil
    end
  end

  defp devices_with_alarms_query(product_id) do
    Device
    |> join(:inner, [d], lh in assoc(d, :latest_health), as: :latest_health)
    |> where([d], d.product_id == ^product_id)
    |> where([latest_health: lh], fragment("?->'alarms' != '{}'", lh.data))
    |> Repo.exclude_deleted()
  end
end

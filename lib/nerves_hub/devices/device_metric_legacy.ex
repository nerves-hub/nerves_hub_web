defmodule NervesHub.Devices.DeviceMetricLegacy do
  @moduledoc """
  The PostgreSQL `device_metrics` table, on its way out.

  Metrics now live in ClickHouse as `NervesHub.Devices.DeviceMetric`.
  `NervesHub.Devices.Metrics` writes both stores while the read paths are moved
  over one at a time; this module and its table go once the last read has
  moved. Nothing new should reach for it.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Changeset
  alias NervesHub.Devices.Device

  @type t :: %__MODULE__{}
  @required_params [:device_id, :key, :value]

  schema "device_metrics" do
    belongs_to(:device, Device)
    field(:key, :string)
    field(:value, :float)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def save(params) do
    %__MODULE__{}
    |> cast(params, @required_params)
    |> validate_required(@required_params)
    |> format_field(:key)
  end

  @doc """
  To use when creating fake metrics with manipulated timestamps
  """
  def save_with_timestamp(params) do
    %__MODULE__{}
    |> cast(params, @required_params ++ [:inserted_at])
    |> validate_required(@required_params)
    |> format_field(:key)
  end

  defp format_field(%Changeset{changes: %{key: key}} = cs, :key) do
    # Just remove spaces for now.
    formatted_key = String.replace(key, " ", "")

    put_change(cs, :key, formatted_key)
  end

  defp format_field(cs, :key), do: cs
end

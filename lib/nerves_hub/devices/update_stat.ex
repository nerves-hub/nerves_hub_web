defmodule NervesHub.Devices.UpdateStat do
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @required [
    :timestamp,
    :device_id,
    :product_id,
    :deployment_id,
    :type,
    :source_firmware_uuid,
    :target_firmware_uuid,
    :update_bytes,
    :saved_bytes
  ]

  # TODO: Add fields for which firmware update it was from and to

  @primary_key false
  schema "update_stats" do
    field(:timestamp, Ch, type: "DateTime64(6, 'UTC')")
    field(:product_id, Ch, type: "UInt64")
    field(:device_id, Ch, type: "UInt64")
    field(:deployment_id, Ch, type: "UInt64")
    field(:type, Ch, type: "LowCardinality(String)")
    field(:source_firmware_uuid, Ch, type: "Nullable(UUID)")
    field(:target_firmware_uuid, Ch, type: "UUID")
    field(:update_bytes, Ch, type: "UInt64")
    # Yes, you can "save" a negative amount of bytes
    # This field represents savings from delta update usage and
    # perhaps other future optimizations
    field(:saved_bytes, Ch, type: "Int64")
  end

  def create_changeset(device, deployment_group, params \\ %{}) do
    params =
      params
      |> Map.put("device_id", device.id)
      |> Map.put("product_id", device.product_id)
      |> Map.put("deployment_id", deployment_group.id)

    %__MODULE__{}
    |> cast(params, @required)
    |> validate_required(@required)
  end
end

defmodule NervesHub.Firmwares.FirmwareDelta do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Firmwares.Firmware

  alias __MODULE__

  @type t :: %__MODULE__{}
  @optional_params []
  @required_params [
    :source_id,
    :target_id,
    :upload_metadata,
    :tool,
    :tool_metadata,
    :size,
    :source_size,
    :target_size
  ]

  schema "firmware_deltas" do
    belongs_to(:source, Firmware)
    belongs_to(:target, Firmware)

    field(:tool, :string)
    # Metadata about the delta that the update tool needs to operate
    field(:tool_metadata, :map)
    field(:size, :integer, default: 0)
    field(:source_size, :integer, default: 0)
    field(:target_size, :integer, default: 0)
    field(:upload_metadata, :map)

    timestamps()
  end

  def changeset(%FirmwareDelta{} = firmware_delta, params) do
    firmware_delta
    |> cast(params, @required_params ++ @optional_params)
    |> validate_required(@required_params)
    |> unique_constraint(:unique_firmware_delta, name: :source_id_target_id_unique_index)
    |> foreign_key_constraint(:source_id, name: :firmware_deltas_source_id_fkey)
    |> foreign_key_constraint(:target_id, name: :firmware_deltas_target_id_fkey)
  end
end

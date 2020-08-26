defmodule NervesHubWebCore.Firmwares.FirmwarePatch do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias NervesHubWebCore.Firmwares.Firmware

  alias __MODULE__

  @type t :: %__MODULE__{}
  @optional_params []
  @required_params [
    :source_id,
    :target_id,
    :upload_metadata
  ]

  schema "firmware_patches" do
    belongs_to(:source, Firmware)
    belongs_to(:target, Firmware)

    field(:upload_metadata, :map)

    timestamps()
  end

  def changeset(%FirmwarePatch{} = patch, params) do
    patch
    |> cast(params, @required_params ++ @optional_params)
    |> validate_required(@required_params)
    |> unique_constraint(:unique_patch, name: :source_id_target_id_unique_index)
    |> foreign_key_constraint(:source_id, name: :firmware_patches_source_id_fkey)
    |> foreign_key_constraint(:target_id, name: :firmware_patches_target_id_fkey)
  end

  def with_firmwares(patch_query) do
    patch_query
    |> preload(:source)
    |> preload(:target)
  end
end

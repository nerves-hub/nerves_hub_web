defmodule NervesHubWebCore.Firmwares.FirmwareDelta do
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

  schema "firmware_deltas" do
    belongs_to(:source, Firmware)
    belongs_to(:target, Firmware)

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

  def with_firmwares(firmware_delta_query) do
    firmware_delta_query
    |> preload(:source)
    |> preload(:target)
  end
end

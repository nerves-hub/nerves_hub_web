defmodule NervesHubWebCore.Firmwares.FirmwareMetadata do
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @required_params [
    :uuid,
    :product,
    :architecture,
    :version,
    :platform
  ]

  @optional_params [
    :author,
    :description,
    :vcs_identifier,
    :misc,
    :patchable
  ]

  @derive Jason.Encoder
  embedded_schema do
    field(:uuid)
    field(:product)
    field(:version)
    field(:architecture)
    field(:patchable)
    field(:platform)
    field(:author)
    field(:description)
    field(:vcs_identifier)
    field(:misc)
  end

  def changeset(%__MODULE__{} = metadata, params) do
    metadata
    |> cast(params, @required_params ++ @optional_params)
    |> validate_required(@required_params)
  end
end

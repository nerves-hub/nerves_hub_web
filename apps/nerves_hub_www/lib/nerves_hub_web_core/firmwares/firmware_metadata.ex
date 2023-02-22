defmodule NervesHubWebCore.Firmwares.FirmwareMetadata do
  use Ecto.Schema

  import Ecto.Changeset

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
    :fwup_version,
    :vcs_identifier,
    :misc
  ]

  @typedoc """
  fwup meta data about firmware

  [read more here](https://github.com/fwup-home/fwup#global-scope)
  """
  @type t :: %__MODULE__{
          architecture: String.t(),
          author: String.t() | nil,
          description: String.t() | nil,
          fwup_version: Version.build() | nil,
          id: Ecto.UUID.t(),
          misc: String.t() | nil,
          platform: String.t(),
          product: String.t(),
          uuid: Ecto.UUID.t(),
          vcs_identifier: String.t() | nil,
          version: Version.build()
        }

  @type metadata :: %{
          :architecture => String.t(),
          :author => String.t() | nil,
          :description => String.t() | nil,
          optional(:fwup_version) => Version.build() | nil,
          :misc => String.t() | nil,
          :platform => String.t(),
          :product => String.t(),
          :uuid => Ecto.UUID.t(),
          :vcs_identifier => String.t() | nil,
          :version => Version.build()
        }

  @derive Jason.Encoder
  embedded_schema do
    field(:uuid)
    field(:product)
    field(:version)
    field(:architecture)
    field(:platform)
    field(:author)
    field(:description)
    field(:fwup_version)
    field(:vcs_identifier)
    field(:misc)
  end

  def changeset(%__MODULE__{} = metadata, params) do
    metadata
    |> cast(params, @required_params ++ @optional_params)
    |> validate_required(@required_params)
  end
end

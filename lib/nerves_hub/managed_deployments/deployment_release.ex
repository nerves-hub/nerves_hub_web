defmodule NervesHub.ManagedDeployments.DeploymentRelease do
  use Ecto.Schema

  import Ecto.Changeset

  alias __MODULE__
  alias NervesHub.Accounts.User
  alias NervesHub.Archives.Archive
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments.DeploymentGroup

  @type t :: %__MODULE__{}

  @required_fields [
    :deployment_group_id,
    :firmware_id,
    :created_by_id
  ]

  @optional_fields [:archive_id]

  schema "deployment_releases" do
    belongs_to(:deployment_group, DeploymentGroup)
    belongs_to(:firmware, Firmware)
    belongs_to(:archive, Archive)
    belongs_to(:user, User, foreign_key: :created_by_id)

    timestamps()
  end

  def changeset(%DeploymentRelease{} = deployment_release, params) do
    deployment_release
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end

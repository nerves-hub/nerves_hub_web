defmodule NervesHub.ManagedDeployments.DeploymentRelease do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

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

    field(:number, :integer)

    timestamps()
  end

  def changeset(%DeploymentRelease{} = deployment_release, params) do
    deployment_release
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> prepare_changes(fn changeset ->
      dg_id = get_field(changeset, :deployment_group_id)
      query = from(DeploymentRelease, where: [deployment_group_id: ^dg_id])
      number = changeset.repo.aggregate(query, :count) + 1
      put_change(changeset, :number, number)
    end)
  end
end

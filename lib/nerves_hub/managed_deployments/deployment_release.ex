defmodule NervesHub.ManagedDeployments.DeploymentRelease do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.AuditLogs
  alias NervesHub.Accounts.User
  alias NervesHub.Archives.Archive
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Products.Product

  alias __MODULE__

  @type t :: %__MODULE__{}

  @required_fields [
    :deployment_group_id,
    :firmware_id,
    :created_by_ref
  ]

  @optional_fields [:archive_id]

  schema "deployment_releases" do
    belongs_to(:deployment_group, DeploymentGroup)
    belongs_to(:firmware, Firmware)
    belongs_to(:archive, Archive)
    belongs_to(:user, User, foreign_key: :created_by_id)
    field(:created_by_ref, :string)

    timestamps()
  end

  def changeset(%DeploymentRelease{} = deployment_release, actor, params) do
    deployment_release
    |> merge_actor(actor)
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  def merge_actor(%DeploymentRelease{} = deployment_release, %User{} = user) do
    %{deployment_release | created_by_id: user.id, created_by_ref: AuditLogs.actor_template(user)}
  end

  def merge_actor(%DeploymentRelease{} = deployment_release, %Product{} = product) do
    %{
      deployment_release
      | created_by_id: nil,
        created_by_ref: AuditLogs.actor_template(product)
    }
  end
end

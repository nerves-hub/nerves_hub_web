defmodule NervesHub.ManagedDeployments.DeploymentRelease do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias __MODULE__
  alias NervesHub.Accounts.User
  alias NervesHub.Archives.Archive
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Repo

  @type t :: %__MODULE__{}

  schema "deployment_releases" do
    belongs_to(:deployment_group, DeploymentGroup)
    belongs_to(:firmware, Firmware)
    belongs_to(:archive, Archive)
    belongs_to(:created_by, User)

    field(:number, :integer)

    timestamps()
  end

  def new_changeset(deployment_group, firmware, archive, user) do
    change(%__MODULE__{})
    |> put_assoc(:deployment_group, deployment_group)
    |> put_assoc(:firmware, firmware)
    |> put_assoc(:archive, archive)
    |> put_assoc(:created_by, user)
    |> put_change(:number, 1)
    |> validate_required([:firmware])
    |> validate_firmware(deployment_group)
    |> validate_change(:created_by, fn :created_by, created_by_assoc ->
      created_by = created_by_assoc.data

      User
      |> join(:inner, [u], o in assoc(u, :orgs))
      |> join(:inner, [_, o], p in assoc(o, :products))
      |> where([u], u.id == ^created_by.id)
      |> where([_, _, p], p.id == ^deployment_group.product_id)
      |> Repo.one()
      |> case do
        nil -> [created_by: "invalid associated user"]
        _user -> []
      end
    end)
    |> prepare_changes(fn changeset ->
      dg = get_field(changeset, :deployment_group)
      query = from(DeploymentRelease, where: [deployment_group_id: ^dg.id])
      number = changeset.repo.aggregate(query, :count) + 1
      put_change(changeset, :number, number)
    end)
  end

  defp validate_firmware(changeset, deployment_group) do
    validate_change(changeset, :firmware, fn :firmware, firmware_assoc ->
      firmware = firmware_assoc.data

      if not is_nil(firmware) && firmware.product_id != deployment_group.product_id do
        [firmware: "invalid firmware selected"]
      else
        []
      end
    end)
  end
end

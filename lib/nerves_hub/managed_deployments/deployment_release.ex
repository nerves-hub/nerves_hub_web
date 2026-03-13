defmodule NervesHub.ManagedDeployments.DeploymentRelease do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias __MODULE__
  alias NervesHub.Accounts.User
  alias NervesHub.Archives.Archive
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Repo

  @type t :: %__MODULE__{}

  schema "deployment_releases" do
    belongs_to(:deployment_group, DeploymentGroup)
    belongs_to(:firmware, Firmware)
    belongs_to(:archive, Archive)
    belongs_to(:user, User, foreign_key: :created_by_id)

    field(:number, :integer)

    timestamps()
  end

  def new_changeset(deployment_group, params, user) do
    %__MODULE__{}
    |> cast(params, [:firmware_id, :archive_id])
    |> put_change(:deployment_group_id, deployment_group.id)
    |> put_change(:created_by_id, user.id)
    |> validate_required([:firmware_id])
    |> validate_change(:firmware_id, fn :firmware_id, firmware_id ->
      Firmwares.get_by_id(deployment_group, firmware_id)
      |> case do
        {:ok, _firmware} -> []
        {:error, _} -> [firmware_id: "invalid firmware selection"]
      end
    end)
    |> validate_change(:created_by_id, fn :created_by_id, created_by_id ->
      User
      |> join(:inner, [u], o in assoc(u, :orgs))
      |> join(:inner, [_, o], p in assoc(o, :products))
      |> where([u], u.id == ^created_by_id)
      |> where([_, _, p], p.id == ^deployment_group.product_id)
      |> Repo.one()
      |> case do
        nil -> [created_by_id: "invalid associated user"]
        _user -> []
      end
    end)
    |> prepare_changes(fn changeset ->
      dg_id = get_field(changeset, :deployment_group_id)
      query = from(DeploymentRelease, where: [deployment_group_id: ^dg_id])
      number = changeset.repo.aggregate(query, :count) + 1
      put_change(changeset, :number, number)
    end)
  end

  def parent_create_changeset(changeset, params, product_id) do
    changeset
    |> cast(params, [:firmware_id, :created_by_id, :number])
    |> validate_required([:firmware_id])
    |> validate_change(:created_by_id, fn :created_by_id, created_by_id ->
      User
      |> join(:inner, [u], o in assoc(u, :orgs))
      |> join(:inner, [_, o], p in assoc(o, :products))
      |> where([u], u.id == ^created_by_id)
      |> where([_, _, p], p.id == ^product_id)
      |> Repo.one()
      |> case do
        nil -> [created_by_id: "invalid associated user"]
        _user -> []
      end
    end)
  end
end

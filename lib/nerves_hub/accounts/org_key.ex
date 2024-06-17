defmodule NervesHub.Accounts.OrgKey do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias NervesHub.Accounts.Org
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Repo
  alias __MODULE__

  @type t :: %__MODULE__{}

  @required_params [:org_id, :name, :key]
  @optional_params []

  schema "org_keys" do
    belongs_to(:org, Org, where: [deleted_at: nil])
    has_many(:firmwares, Firmware)

    field(:name, :string)
    field(:key, :string)

    timestamps()
  end

  def changeset(%OrgKey{} = org, params) do
    org
    |> cast(params, @required_params ++ @optional_params)
    |> validate_required(@required_params)
    |> unique_constraint(:name, name: :org_keys_org_id_name_index)
    |> unique_constraint(:key, name: :org_keys_org_id_key_index)
  end

  def update_changeset(%OrgKey{id: _} = org_key, params) do
    # don't allow org_id to change
    org_key
    |> cast(params, @required_params -- [:org_id])
    |> validate_required(@required_params)
    |> unique_constraint(:name, name: :org_keys_org_id_name_index)
    |> unique_constraint(:key, name: :org_keys_org_id_key_index)
  end

  def delete_changeset(%OrgKey{id: _} = org_key, params) do
    org_key
    |> cast(params, @required_params ++ @optional_params)
    |> foreign_key_constraint(:firmwares,
      name: :firmwares_tenant_key_id_fkey,
      message: "Firmware exists which uses the Signing Key"
    )
  end

  def with_org(%OrgKey{} = o) do
    o
    |> Repo.preload(:org)
  end

  def with_org(org_key_query) do
    org_key_query
    |> preload(:org)
  end
end

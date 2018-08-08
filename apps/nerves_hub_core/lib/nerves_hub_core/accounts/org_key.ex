defmodule NervesHubCore.Accounts.OrgKey do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHubCore.Accounts.Org
  alias NervesHubCore.Firmwares.Firmware
  alias __MODULE__

  @type t :: %__MODULE__{}

  @required_params [:org_id, :name, :key]
  @optional_params []

  schema "org_keys" do
    belongs_to(:org, Org)
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
    |> unique_constraint(:key)
  end

  def update_changeset(%OrgKey{id: _} = org, params) do
    # don't allow org_id to change
    org
    |> cast(params, @required_params -- [:org_id])
    |> validate_required(@required_params)
    |> unique_constraint(:name, name: :org_keys_org_id_name_index)
    |> unique_constraint(:key)
  end
end

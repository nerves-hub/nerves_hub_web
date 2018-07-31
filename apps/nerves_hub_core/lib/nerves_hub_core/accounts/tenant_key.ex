defmodule NervesHubCore.Accounts.TenantKey do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHubCore.Accounts.Tenant
  alias NervesHubCore.Firmwares.Firmware
  alias __MODULE__

  @type t :: %__MODULE__{}

  schema "tenant_keys" do
    belongs_to(:tenant, Tenant)
    has_many(:firmwares, Firmware)

    field(:name, :string)
    field(:key, :string)

    timestamps()
  end

  def changeset(%TenantKey{} = tenant, params) do
    tenant
    |> cast(params, [:tenant_id, :name, :key])
    |> validate_required([:tenant_id, :name, :key])
    |> unique_constraint(:name, name: :tenant_keys_tenant_id_name_index)
    |> unique_constraint(:key)
  end
end

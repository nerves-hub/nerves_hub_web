defmodule Beamware.Accounts.TenantKey do
  use Ecto.Schema

  import Ecto.Changeset

  alias Beamware.Accounts.Tenant
  alias Beamware.Firmwares.Firmware
  alias __MODULE__

  @type t :: %__MODULE__{}

  schema "tenant_keys" do
    belongs_to(:tenant, Tenant)
    has_many(:firmware, Firmware)

    field(:name, :string)
    field(:key, :string)

    timestamps()
  end

  def changeset(%TenantKey{} = tenant, params) do
    tenant
    |> cast(params, [:tenant_id, :name, :key])
    |> validate_required([:tenant_id, :name, :key])
    |> unique_constraint(:name, name: :tenant_keys_tenant_id_name_index)
  end
end

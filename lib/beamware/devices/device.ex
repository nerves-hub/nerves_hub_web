defmodule Beamware.Devices.Device do
  use Ecto.Schema

  import Ecto.Changeset

  alias Beamware.Accounts.Tenant
  alias __MODULE__

  @type t :: %__MODULE__{}

  schema "devices" do
    belongs_to(:tenant, Tenant)

    field(:identifier, :string)
    field(:description, :string)
    field(:product, :string)
    field(:platform, :string)
    field(:current_version, :string)
    field(:target_version, :string)
    field(:last_communication, :utc_datetime)
    field(:architecture, :string)
    field(:tags, {:array, :string})

    timestamps()
  end

  def creation_changeset(%Device{} = device, params) do
    device
    |> cast(params, [:identifier, :description, :tags, :architecture, :platform])
    |> validate_required([:identifier, :tags, :architecture, :platform])
    |> validate_length(:tags, min: 1)
    |> unique_constraint(:identifier, name: :devices_tenant_id_identifier_index)
  end

  def update_changeset(%Device{} = device, params) do
    device
    |> cast(params, [:tags])
    |> validate_required([:tags])
    |> validate_length(:tags, min: 1)
  end
end

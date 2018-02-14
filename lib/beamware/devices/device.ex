defmodule Beamware.Devices.Device do
  use Ecto.Schema

  alias Beamware.Accounts.Tenant

  schema "devices" do
    belongs_to(:tenant, Tenant)

    field(:identifier, :string)
    field(:current_version, :string)
    field(:target_version, :string)
    field(:last_communication, :utc_datetime)
    field(:architecture, :string)
    field(:tags, {:array, :string})

    timestamps()
  end
end

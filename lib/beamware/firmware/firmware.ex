defmodule Beamware.Firmwares.Firmware do
  use Ecto.Schema

  import Ecto.Changeset

  alias Beamware.Accounts.{Tenant}
  alias __MODULE__

  @type t :: %__MODULE__{}

  schema "firmwares" do
    belongs_to(:tenant, Tenant)

    field(:filename, :string)
    field(:product, :string)
    field(:platform, :string)
    field(:architecture, :string)
    field(:timestamp, :utc_datetime)
    field(:signed, :boolean)
    field(:tenant_key_id, :integer)
    field(:metadata, :string)
    field(:upload_metadata, :map)

    timestamps()
  end

  def changeset(%Firmware{} = firmware, params) do
    fields = [
      :tenant_id,
      :filename,
      :product,
      :platform,
      :architecture,
      :timestamp,
      :signed,
      :tenant_key_id,
      :metadata,
      :upload_metadata
    ]

    firmware
    |> cast(params, fields)
    |> validate_required(fields -- [:tenant_key_id])
  end
end

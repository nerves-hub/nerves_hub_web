defmodule NervesHub.Firmwares.FirmwareTransfer do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.Org

  @type t :: %__MODULE__{}
  @primary_key {:id, :binary_id, autogenerate: true}

  @params [
    :org_id,
    :firmware_uuid,
    :remote_ip,
    :bytes_total,
    :bytes_sent,
    :timestamp
  ]

  schema "firmware_transfers" do
    field(:bytes_sent, :integer)
    field(:bytes_total, :integer)
    field(:firmware_uuid)
    field(:remote_ip)
    field(:timestamp, :utc_datetime)

    belongs_to(:org, Org, where: [deleted_at: nil])
  end

  def changeset(%__MODULE__{} = transfer, params) do
    transfer
    |> cast(params, @params)
    |> validate_required(@params)
    |> foreign_key_constraint(:org_id, name: :firmware_transfers_org_id_fkey)
  end
end

defmodule NervesHub.Accounts.OrgMetric do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.Org

  @type t :: %__MODULE__{}
  @primary_key {:id, :binary_id, autogenerate: true}

  @params [
    :org_id,
    :devices,
    :bytes_stored,
    :timestamp
  ]

  schema "org_metrics" do
    field(:bytes_stored, :integer)
    field(:devices, :integer)
    field(:timestamp, :utc_datetime)

    belongs_to(:org, Org, where: [deleted_at: nil])
  end

  def changeset(%__MODULE__{} = org_metric, params) do
    org_metric
    |> cast(params, @params)
    |> validate_required(@params)
    |> foreign_key_constraint(:org_id, name: :firmware_transfers_org_id_fkey)
  end
end

defmodule NervesHubWebCore.Accounts.OrgMetric do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHubWebCore.Accounts.Org

  @type t :: %__MODULE__{}
  @primary_key {:id, :binary_id, autogenerate: true}

  @params [
    :org_id,
    :devices,
    :bytes_stored,
    :timestamp
  ]

  schema "org_metrics" do
    belongs_to(:org, Org)

    field(:devices, :integer)
    field(:bytes_stored, :integer)
    field(:timestamp, :utc_datetime)
  end

  def changeset(%__MODULE__{} = org_metric, params) do
    org_metric
    |> cast(params, @params)
    |> validate_required(@params)
    |> foreign_key_constraint(:org_id, name: :firmware_transfers_org_id_fkey)
  end
end

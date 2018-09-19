defmodule NervesHubCore.Accounts.OrgLimit do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHubCore.Accounts.Org
  alias __MODULE__

  @type t :: %__MODULE__{}

  @required_params [:org_id]
  @optional_params [:firmware_size]

  schema "org_limits" do
    belongs_to(:org, Org)

    # 160 Mb
    field(:firmware_size, :integer, default: 167_772_160)

    timestamps()
  end

  def changeset(%OrgLimit{} = org_limit, params) do
    org_limit
    |> cast(params, @required_params ++ @optional_params)
    |> validate_required(@required_params)
    |> unique_constraint(:org_id)
  end

  def update_changeset(%OrgLimit{id: _} = org_limit, params) do
    # don't allow org_id to change
    org_limit
    |> cast(params, @required_params -- [:org_id])
    |> validate_required(@required_params)
    |> unique_constraint(:org_id)
  end
end

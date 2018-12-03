defmodule NervesHubWebCore.Accounts.OrgLimit do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHubWebCore.Accounts.Org
  alias __MODULE__

  @type t :: %__MODULE__{}

  @required_params [:org_id]
  @optional_params [
    :devices,
    :firmware_per_product,
    :firmware_size,
    :firmware_ttl_seconds_default,
    :firmware_ttl_seconds
  ]

  @defaults [
    # Max number of devices per org
    devices: 5,
    # Max number of firmwares per product
    firmware_per_product: 5,
    # Max firmware size (160 Mb)
    firmware_size: 167_772_160,
    # Default firmwre ttl seconds (7 days)
    firmware_ttl_seconds_default: 604_800,
    # Max firmwre ttl seconds (7 days)
    firmware_ttl_seconds: 604_800
  ]

  schema "org_limits" do
    belongs_to(:org, Org)

    field(:devices, :integer, default: @defaults[:devices])
    field(:firmware_per_product, :integer, default: @defaults[:firmware_per_product])
    field(:firmware_size, :integer, default: @defaults[:firmware_size])

    field(:firmware_ttl_seconds_default, :integer,
      default: @defaults[:firmware_ttl_seconds_default]
    )

    field(:firmware_ttl_seconds, :integer, default: @defaults[:firmware_ttl_seconds])

    timestamps()
  end

  def defaults(), do: @defaults

  def changeset(%OrgLimit{} = org_limit, params) do
    org_limit
    |> cast(params, @required_params ++ @optional_params)
    |> validate_required(@required_params)
    |> unique_constraint(:org_id)
  end

  def update_changeset(%OrgLimit{id: _} = org_limit, params) do
    # don't allow org_id to change
    org_limit
    |> cast(params, (@required_params -- [:org_id]) ++ @optional_params)
    |> validate_required(@required_params)
    |> unique_constraint(:org_id)
  end
end

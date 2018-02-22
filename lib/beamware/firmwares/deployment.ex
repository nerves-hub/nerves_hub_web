defmodule Beamware.Firmwares.Deployment do
  use Ecto.Schema

  import Ecto.Changeset

  alias Beamware.Accounts.Tenant
  alias Beamware.Firmwares.Firmware
  alias __MODULE__

  @type t :: %__MODULE__{}

  schema "deployments" do
    belongs_to(:tenant, Tenant)
    belongs_to(:firmware, Firmware)

    field(:name, :string)
    field(:conditions, :map)
    field(:status, :string)

    timestamps()
  end

  def changeset(%Deployment{} = deployment, params) do
    fields = [
      :name,
      :conditions,
      :status
    ]

    deployment
    |> cast(params, fields)
    |> validate_required(fields)
  end
end

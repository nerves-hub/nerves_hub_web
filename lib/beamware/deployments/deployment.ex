defmodule Beamware.Deployments.Deployment do
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
      :status,
      :firmware_id
    ]

    deployment
    |> cast(params, fields)
    |> validate_required(fields)
    |> validate_change(:conditions, fn :conditions, conditions ->
      types = %{tags: {:array, :string}, version: :string}

      changeset =
        {%{}, types}
        |> cast(conditions, Map.keys(types))
        |> validate_required([:version, :tags])
        |> validate_length(:tags, min: 1)
        |> validate_change(:version, fn :version, version ->
          if Version.parse_requirement(version) == :error do
            [version: "Must be valid Elixir version requirement string"]
          else
            []
          end
        end)

      changeset.errors
    end)
  end
end

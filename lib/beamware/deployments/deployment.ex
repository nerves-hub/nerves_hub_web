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
    field(:is_active, :boolean)

    timestamps()
  end

  def changeset(%Deployment{} = deployment, params) do
    fields = [
      :name,
      :conditions,
      :is_active,
      :firmware_id
    ]

    deployment
    |> cast(params, fields)
    |> validate_required(fields)
    |> validate_change(:conditions, fn :conditions, conditions ->
      types = %{tags: {:array, :string}, version: :string}

      version =
        case Map.get(conditions, "version") do
          "" -> nil
          v -> v
        end

      conditions = Map.put(conditions, "version", version)

      changeset =
        {%{}, types}
        |> cast(conditions, Map.keys(types))
        |> validate_required([:tags])
        |> validate_length(:tags, min: 1)
        |> validate_change(:version, fn :version, version ->
          if not is_nil(version) and Version.parse_requirement(version) == :error do
            [version: "Must be valid Elixir version requirement string"]
          else
            []
          end
        end)

      changeset.errors
    end)
  end
end

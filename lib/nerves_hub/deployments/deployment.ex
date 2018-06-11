defmodule NervesHub.Deployments.Deployment do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.Tenant
  alias NervesHub.Firmwares.Firmware
  alias __MODULE__

  @type t :: %__MODULE__{}
  @required_fields [:tenant_id, :firmware_id, :name, :conditions, :is_active]
  @optional_fields []

  schema "deployments" do
    belongs_to(:tenant, Tenant)
    belongs_to(:firmware, Firmware)

    field(:name, :string)
    field(:conditions, :map)
    field(:is_active, :boolean)

    timestamps()
  end

  def edit_changeset(%Deployment{} = deployment, params) do
    fields = [
      :name,
      :conditions,
      :is_active
    ]

    deployment
    |> cast(params, fields)
    |> validate_required(fields)
    |> validate_conditions()
  end

  def changeset(%Deployment{} = deployment, params) do
    deployment
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_conditions()
  end

  defp validate_conditions(changeset, _options \\ []) do
    validate_change(changeset, :conditions, fn :conditions, conditions ->
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

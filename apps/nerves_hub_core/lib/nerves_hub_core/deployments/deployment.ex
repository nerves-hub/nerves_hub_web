defmodule NervesHubCore.Deployments.Deployment do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias NervesHubCore.Firmwares.Firmware
  alias NervesHubCore.Products.Product

  alias __MODULE__

  @type t :: %__MODULE__{}
  @required_fields [:product_id, :firmware_id, :name, :conditions, :is_active]
  @optional_fields []

  schema "deployments" do
    belongs_to(:firmware, Firmware)
    belongs_to(:product, Product)

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

  def creation_changeset(%Deployment{} = deployment, params) do
    deployment
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_change(:is_active, fn :is_active, is_active ->
      creation_errors(:is_active, is_active)
    end)
  end

  defp creation_errors(:is_active, is_active) do
    if is_active do
      [is_active: "cannot be true on creation"]
    else
      []
    end
  end

  def with_firmware(deployment_query) do
    deployment_query
    |> preload(:firmware)
  end

  def with_product(deployment_query) do
    deployment_query
    |> preload(:product)
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

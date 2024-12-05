defmodule NervesHub.Deployments.Deployment do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias NervesHub.Accounts.Org
  alias NervesHub.Archives.Archive
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Products.Product
  alias NervesHub.Repo

  alias __MODULE__

  @type t :: %__MODULE__{}

  @required_fields [
    :org_id,
    :firmware_id,
    :name,
    :conditions,
    :is_active,
    :product_id,
    :concurrent_updates,
    :inflight_update_expiration_minutes
  ]

  @optional_fields [
    :archive_id,
    :device_failure_threshold,
    :device_failure_rate_seconds,
    :device_failure_rate_amount,
    :failure_threshold,
    :failure_rate_seconds,
    :failure_rate_amount,
    :healthy,
    :penalty_timeout_minutes,
    :connecting_code,
    :total_updating_devices,
    :current_updated_devices,
    :recalculation_type
  ]

  schema "deployments" do
    belongs_to(:firmware, Firmware)
    belongs_to(:product, Product, where: [deleted_at: nil])
    belongs_to(:org, Org, where: [deleted_at: nil])
    belongs_to(:archive, Archive)

    has_many(:inflight_updates, InflightUpdate)

    field(:conditions, :map)
    field(:device_failure_threshold, :integer, default: 3)
    field(:device_failure_rate_seconds, :integer, default: 180)
    field(:device_failure_rate_amount, :integer, default: 5)
    field(:failure_threshold, :integer, default: 50)
    field(:failure_rate_seconds, :integer, default: 300)
    field(:failure_rate_amount, :integer, default: 5)
    field(:is_active, :boolean)
    field(:name, :string)
    field(:healthy, :boolean, default: true)
    field(:penalty_timeout_minutes, :integer, default: 1440)
    field(:connecting_code, :string)
    field(:concurrent_updates, :integer, default: 10)
    field(:total_updating_devices, :integer, default: 0)
    field(:current_updated_devices, :integer, default: 0)
    field(:inflight_update_expiration_minutes, :integer, default: 60)
    # TODO: (nshoes) this column is unused, remove after Managed Deploys is done
    field(:recalculation_type, Ecto.Enum, values: [:device, :calculator_queue], default: :device)

    timestamps()
  end

  def creation_changeset(%Deployment{} = deployment, params) do
    # set product_id by getting it from firmware
    with_product_id = handle_product_id(deployment, params)

    deployment
    |> cast(with_product_id, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:name, name: :deployments_product_id_name_index)
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

  defp handle_product_id(%Deployment{}, %{firmware: %Firmware{product_id: p_id}} = params) do
    params |> Map.put(:product_id, p_id)
  end

  defp handle_product_id(%Deployment{firmware: %Firmware{product_id: p_id}}, params) do
    params |> Map.put(:product_id, p_id)
  end

  defp handle_product_id(%Deployment{} = d, %{firmware_id: f_id} = params) do
    handle_product_id(d, params |> Map.put(:firmware, Firmware |> Repo.get!(f_id)))
  end

  defp handle_product_id(%Deployment{firmware_id: nil}, params) do
    params
  end

  defp handle_product_id(%Deployment{} = d, params) do
    handle_product_id(d |> with_firmware(), params)
  end

  def changeset(%Deployment{} = deployment, params) do
    deployment
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:name, name: :deployments_product_id_name_index)
    |> prepare_changes(fn changeset ->
      if changeset.changes[:firmware_id] do
        put_change(changeset, :current_updated_devices, 0)
      else
        changeset
      end
    end)
    |> validate_conditions()
  end

  def with_firmware(%Deployment{firmware: %Firmware{}} = d), do: d

  def with_firmware(%Deployment{} = d) do
    d
    |> Repo.preload(:firmware)
  end

  def with_firmware(deployment_query) do
    deployment_query
    |> preload(:firmware)
  end

  def with_product(%Deployment{product: %Product{}} = d), do: d

  def with_product(%Deployment{} = d) do
    d
    |> Repo.preload(:product)
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

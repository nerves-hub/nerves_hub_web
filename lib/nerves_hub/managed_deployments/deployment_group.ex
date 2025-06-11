defmodule NervesHub.ManagedDeployments.DeploymentGroup do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias NervesHub.Accounts.Org
  alias NervesHub.Archives.Archive
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments.DeploymentRelease
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
    :queue_management,
    :delta_updatable
  ]

  @derive {Phoenix.Param, key: :name}
  schema "deployments" do
    belongs_to(:firmware, Firmware)
    belongs_to(:product, Product, where: [deleted_at: nil])
    belongs_to(:org, Org, where: [deleted_at: nil])
    belongs_to(:archive, Archive)

    has_many(:inflight_updates, InflightUpdate, foreign_key: :deployment_id)
    has_many(:devices, Device, foreign_key: :deployment_id, on_delete: :nilify_all)
    has_many(:deployment_releases, DeploymentRelease)

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
    field(:queue_management, Ecto.Enum, values: [:FIFO, :LIFO], default: :FIFO)
    field(:delta_updatable, :boolean, default: false)

    # TODO: (nshoes) this column is unused, remove after 1st March
    # field(:recalculation_type, Ecto.Enum, values: [:device, :calculator_queue], default: :device)

    field(:device_count, :integer, virtual: true)

    # TODO: (joshk) this column is unused, remove after 1st May
    # field(:orchestrator_strategy, Ecto.Enum,
    #   values: [:multi, :distributed],
    #   default: :distributed
    # )

    timestamps()
  end

  def create_changeset(%DeploymentGroup{} = deployment, params) do
    base_changeset(deployment, params)
  end

  def update_changeset(%DeploymentGroup{} = deployment, params) do
    base_changeset(deployment, params)
    |> prepare_changes(fn changeset ->
      if changeset.changes[:firmware_id] do
        put_change(changeset, :current_updated_devices, 0)
      else
        changeset
      end
    end)
  end

  defp base_changeset(%DeploymentGroup{} = deployment, params) do
    deployment
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:name, name: :deployments_product_id_name_index)
    |> validate_conditions()
  end

  def with_firmware(%DeploymentGroup{firmware: %Firmware{}} = d), do: d

  def with_firmware(%DeploymentGroup{} = d) do
    d
    |> Repo.preload(:firmware)
  end

  def with_firmware(query), do: preload(query, :firmware)

  def with_product(%DeploymentGroup{product: %Product{}} = d), do: d

  def with_product(%DeploymentGroup{} = d) do
    d
    |> Repo.preload(:product)
  end

  def with_product(query), do: preload(query, :product)

  defp validate_conditions(changeset) do
    validate_change(changeset, :conditions, fn
      :conditions, conditions when conditions == %{} ->
        [conditions: "can't be blank"]

      :conditions, %{"version" => nil} ->
        [version: "can't be blank"]

      :conditions, conditions ->
        types = %{tags: {:array, :string}, version: :string}
        # merge the new conditions with the existing ones so that we can
        # update tags and version independently
        conditions = Map.merge(changeset.data.conditions || %{}, conditions)

        changeset =
          {%{}, types}
          # allow "" as valid value for `version`
          |> cast(conditions, Map.keys(types), empty_values: [nil])
          |> validate_required([:tags])
          |> validate_change(
            :version,
            fn
              :version, "" ->
                []

              :version, nil ->
                [version: "can't be nil"]

              :version, version ->
                if Version.parse_requirement(version) == :error do
                  [version: "must be valid Elixir version requirement string"]
                else
                  []
                end
            end
          )

        changeset.errors
    end)
  end
end

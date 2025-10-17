defmodule NervesHub.ManagedDeployments.DeploymentGroup do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias NervesHub.Accounts.Org
  alias NervesHub.Archives
  alias NervesHub.Archives.Archive
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Devices.UpdateStat
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments.DeploymentRelease
  alias NervesHub.Products.Product

  alias __MODULE__

  @type t :: %__MODULE__{}

  @numeric_fields_with_defaults [
    :concurrent_updates,
    :device_failure_threshold,
    :device_failure_rate_seconds,
    :device_failure_rate_amount,
    :failure_threshold,
    :inflight_update_expiration_minutes,
    :penalty_timeout_minutes
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
    has_many(:update_stats, UpdateStat, on_delete: :nilify_all, foreign_key: :deployment_id)

    embeds_one :conditions, __MODULE__.Conditions, primary_key: false, on_replace: :update do
      field(:version, :string, default: "")
      field(:tags, NervesHub.Types.Tag, default: [])
    end

    field(:device_failure_threshold, :integer, default: 3)
    field(:device_failure_rate_seconds, :integer, default: 180)
    field(:device_failure_rate_amount, :integer, default: 5)
    field(:failure_threshold, :integer, default: 50)
    field(:is_active, :boolean, default: false)
    field(:name, :string)
    field(:healthy, :boolean, default: true)
    field(:penalty_timeout_minutes, :integer, default: 1440)
    field(:connecting_code, :string)
    field(:concurrent_updates, :integer, default: 10)
    field(:total_updating_devices, :integer, default: 0)
    field(:current_updated_devices, :integer, default: 0)
    field(:inflight_update_expiration_minutes, :integer, default: 60)
    field(:queue_management, Ecto.Enum, values: [:FIFO, :LIFO], default: :FIFO)

    field(:delta_updatable, :boolean, default: true)

    field(:status, Ecto.Enum, values: [:ready, :preparing], default: :ready)

    field(:device_count, :integer, virtual: true)

    # TODO: (joshk) this column is unused, remove after 1st May
    # field(:orchestrator_strategy, Ecto.Enum,
    #   values: [:multi, :distributed],
    #   default: :distributed
    # )

    timestamps()
  end

  @spec create_changeset(map(), Product.t()) :: Ecto.Changeset.t()
  def create_changeset(params, product) do
    %DeploymentGroup{}
    |> cast(params, [:name, :delta_updatable, :firmware_id])
    |> cast_and_validate_firmware(product)
    |> validate_required([:name, :delta_updatable])
    |> unique_constraint(:name, name: :deployments_product_id_name_index)
    |> cast_embed(:conditions, required: true, with: &conditions_changeset/2)
  end

  @spec update_changeset(DeploymentGroup.t(), map()) :: Ecto.Changeset.t()
  def update_changeset(%DeploymentGroup{} = deployment, params) do
    deployment
    |> cast(params, [
      :name,
      :is_active,
      :delta_updatable,
      :connecting_code,
      :queue_management,
      :firmware_id,
      :archive_id
    ])
    |> cast_and_validate_numeric_fields(params)
    |> cast_embed(:conditions, required: true, with: &conditions_changeset/2)
    |> cast_and_validate_firmware()
    |> cast_and_validate_archive()
    |> validate_required([:name, :delta_updatable, :is_active, :queue_management])
    |> unique_constraint(:name, name: :deployments_product_id_name_index)
    |> prepare_current_updated_devices()
    |> prepare_device_count()
    |> prepare_status()
  end

  defp cast_and_validate_numeric_fields(changeset, params) do
    changeset
    |> cast(params, @numeric_fields_with_defaults, empty_values: [nil])
    |> validate_number(:concurrent_updates, greater_than: 0)
    |> validate_number(:device_failure_threshold, greater_than: 0)
    |> validate_number(:device_failure_rate_seconds, greater_than_or_equal_to: 60)
    |> validate_number(:device_failure_rate_amount, greater_than: 0)
    |> validate_number(:failure_threshold, greater_than: 0)
    |> validate_number(:inflight_update_expiration_minutes, greater_than_or_equal_to: 30)
    |> validate_number(:penalty_timeout_minutes, greater_than_or_equal_to: 60)
  end

  defp cast_and_validate_firmware(changeset, product \\ nil) do
    product = product || %Product{id: changeset.data.product_id}

    if firmware_id = changeset.changes[:firmware_id] do
      case Firmwares.get_firmware(product, firmware_id) do
        {:ok, firmware} ->
          changeset
          |> put_change(:org_id, firmware.org_id)
          |> put_change(:product_id, firmware.product_id)
          |> put_change(:firmware_id, firmware.id)
          |> assoc_constraint(:org)
          |> assoc_constraint(:product)
          |> assoc_constraint(:firmware)

        {:error, _} ->
          add_error(changeset, :firmware_id, "does not exist")
      end
    else
      changeset
      |> validate_required([:firmware_id])
    end
  end

  defp cast_and_validate_archive(changeset) do
    if archive_id = changeset.changes[:archive_id] do
      %Product{id: changeset.data.product_id}
      |> Archives.get_by_product_and_id(archive_id)
      |> case do
        {:ok, archive} ->
          changeset
          |> put_change(:archive_id, archive.id)
          |> assoc_constraint(:archive)

        {:error, _} ->
          add_error(changeset, :archive_id, "invalid archive")
      end
    else
      changeset
    end
  end

  defp prepare_current_updated_devices(changeset) do
    prepare_changes(changeset, fn changeset ->
      if changeset.changes[:firmware_id] do
        put_change(changeset, :current_updated_devices, 0)
      else
        changeset
      end
    end)
  end

  defp prepare_device_count(changeset) do
    prepare_changes(changeset, fn changeset ->
      device_count =
        Device
        |> select([d], count(d))
        |> where([d], d.deployment_id == ^changeset.data.id)
        |> changeset.repo.one()

      put_change(changeset, :device_count, device_count)
    end)
  end

  defp prepare_status(changeset) do
    prepare_changes(changeset, fn changeset ->
      case changeset do
        %{changes: %{delta_updatable: true}} = changeset ->
          put_change(changeset, :status, :preparing)

        %{changes: %{delta_updatable: false}} = changeset ->
          put_change(changeset, :status, :ready)

        %{changes: %{is_active: true}} = changeset ->
          put_change(changeset, :status, :preparing)

        changeset ->
          changeset
      end
    end)
  end

  def update_status_changeset(%DeploymentGroup{} = deployment, params) do
    deployment
    |> cast(params, [:status])
    |> validate_required([:status])
  end

  def conditions_changeset(conditions, attrs) do
    conditions
    |> cast(attrs, [:tags, :version], empty_values: [""])
    |> then(fn changeset ->
      if Map.has_key?(changeset.changes, :version) && is_nil(changeset.changes.version) do
        put_change(changeset, :version, "")
      else
        changeset
      end
    end)
    |> then(fn changeset ->
      if Map.has_key?(changeset.changes, :tags) && is_nil(changeset.changes.tags) do
        put_change(changeset, :tags, [])
      else
        changeset
      end
    end)
    |> validate_change(
      :version,
      fn
        :version, "" ->
          []

        :version, version ->
          if Version.parse_requirement(version) == :error do
            [version: "must be valid Elixir version requirement string"]
          else
            []
          end
      end
    )
  end
end

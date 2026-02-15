defmodule NervesHub.ManagedDeployments.DeploymentGroup do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias __MODULE__
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
  alias NervesHub.Types.Tag

  @type t :: %__MODULE__{}

  @numeric_fields_with_defaults [
    :concurrent_updates,
    :priority_queue_concurrent_updates,
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
    has_many(:deployment_releases, DeploymentRelease, on_delete: :delete_all)
    has_many(:update_stats, UpdateStat, on_delete: :nilify_all, foreign_key: :deployment_id)

    embeds_one :conditions, __MODULE__.Conditions, primary_key: false, on_replace: :update do
      field(:version, :string, default: "")
      field(:tags, Tag, default: [])
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

    field(:priority_queue_enabled, :boolean, default: false)
    field(:priority_queue_concurrent_updates, :integer, default: 5)
    field(:priority_queue_firmware_version_threshold, :string)

    field(:release_network_interfaces, {:array, Ecto.Enum},
      values: [:wifi, :ethernet, :cellular, :unknown],
      default: []
    )

    field(:release_tags, Tag, default: [])

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
      :archive_id,
      :priority_queue_enabled,
      :priority_queue_firmware_version_threshold,
      :release_network_interfaces,
      :release_tags
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
    |> validate_number(:priority_queue_concurrent_updates, greater_than: 0)
    |> validate_number(:device_failure_threshold, greater_than: 0)
    |> validate_number(:device_failure_rate_seconds, greater_than_or_equal_to: 60)
    |> validate_number(:device_failure_rate_amount, greater_than: 0)
    |> validate_number(:failure_threshold, greater_than: 0)
    |> validate_number(:inflight_update_expiration_minutes, greater_than_or_equal_to: 30)
    |> validate_number(:penalty_timeout_minutes, greater_than_or_equal_to: 60)
    |> normalize_priority_queue_threshold()
    |> validate_priority_queue_version_threshold()
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
      cond do
        # deployment is not active
        not get_field(changeset, :is_active) ->
          put_change(changeset, :status, :ready)

        # deployment is has been switched to active
        get_change(changeset, :is_active) ->
          put_change(changeset, :status, :preparing)

        # deltas have been turned on
        get_change(changeset, :delta_updatable) ->
          put_change(changeset, :status, :preparing)

        # deltas are on and firmware id has changed
        changed?(changeset, :firmware_id) && get_field(changeset, :delta_updatable) ->
          put_change(changeset, :status, :preparing)

        # deltas are off and firmware id has changed
        changed?(changeset, :firmware_id) && not get_field(changeset, :delta_updatable) ->
          put_change(changeset, :status, :ready)

        true ->
          changeset
      end
    end)
  end

  def update_status_changeset(%DeploymentGroup{} = deployment, params) do
    deployment
    |> cast(params, [:status])
    |> validate_required([:status])
  end

  defp normalize_priority_queue_threshold(changeset) do
    if get_change(changeset, :priority_queue_firmware_version_threshold) == "" do
      put_change(changeset, :priority_queue_firmware_version_threshold, nil)
    else
      changeset
    end
  end

  defp validate_priority_queue_version_threshold(changeset) do
    threshold = get_field(changeset, :priority_queue_firmware_version_threshold)

    if threshold do
      case Version.parse(threshold) do
        {:ok, _} ->
          changeset

        :error ->
          add_error(
            changeset,
            :priority_queue_firmware_version_threshold,
            "must be a valid semantic version"
          )
      end
    else
      changeset
    end
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

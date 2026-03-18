defmodule NervesHub.ManagedDeployments.DeploymentGroup do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias __MODULE__
  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.User
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Devices.UpdateStat
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments.DeploymentRelease
  alias NervesHub.Products.Product
  alias NervesHub.Repo
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
    belongs_to(:product, Product, where: [deleted_at: nil])
    belongs_to(:org, Org, where: [deleted_at: nil])

    has_many(:inflight_updates, InflightUpdate, foreign_key: :deployment_id)
    has_many(:devices, Device, foreign_key: :deployment_id, on_delete: :nilify_all)
    has_many(:deployment_releases, DeploymentRelease, on_delete: :delete_all)
    has_many(:update_stats, UpdateStat, on_delete: :nilify_all, foreign_key: :deployment_id)

    belongs_to(:current_release, DeploymentRelease, foreign_key: :current_deployment_release_id)

    embeds_one :conditions, __MODULE__.Conditions, primary_key: false, on_replace: :update do
      field(:version, :string, default: "")
      field(:tags, Tag, default: [])
    end

    field(:platform, :string, writable: :insert)
    field(:architecture, :string, writable: :insert)

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

    field(:status, Ecto.Enum, values: [:ready, :preparing, :deltas_failed, :unknown_error], default: :ready)

    field(:priority_queue_enabled, :boolean, default: false)
    field(:priority_queue_concurrent_updates, :integer, default: 5)
    field(:priority_queue_firmware_version_threshold, :string)

    field(:release_network_interfaces, {:array, Ecto.Enum},
      values: [:wifi, :ethernet, :cellular, :unknown],
      default: []
    )

    field(:release_tags, Tag, default: [])

    field(:releases_count, :integer, virtual: true)
    field(:device_count, :integer, virtual: true)

    # dummy field so we can use this in the 'create deployment group' form (changeset)
    field(:firmware, :any, virtual: true)

    # TODO: (joshk) this column is unused, remove after 1st May
    # field(:orchestrator_strategy, Ecto.Enum,
    #   values: [:multi, :distributed],
    #   default: :distributed
    # )

    timestamps()
  end

  @doc """
  This changeset creates a DeploymentGroup and its first DeploymentRelease.

  When a DeploymentGroup is created, the platform and architecture of the firmware is saved
  and used for restricting future releases.

  A virtual field for `firmware` is used for simplifying the UI form (and errors), as well
  as the API post payload and errors.
  """
  @spec create_changeset(map(), Product.t(), Firmware.t(), User.t()) :: Ecto.Changeset.t()
  def create_changeset(params, product, firmware, user) do
    %DeploymentGroup{}
    |> cast(params, [:name, :delta_updatable, :platform, :architecture])
    |> cast_embed(:conditions, required: true, with: &conditions_changeset/2)
    |> put_change(:product_id, product.id)
    |> put_change(:org_id, product.org_id)
    |> put_change(:firmware, firmware)
    |> maybe_add_platform()
    |> maybe_add_architecture()
    |> validate_required([:name, :delta_updatable, :product_id, :org_id, :firmware])
    |> validate_firmware(product)
    |> validate_platform()
    |> validate_architecture()
    |> unique_constraint(:name, name: :deployments_product_id_name_index)
    |> then(fn changeset ->
      first_release = first_release_changeset(product, get_field(changeset, :firmware), user)

      put_assoc(changeset, :deployment_releases, [first_release])
    end)
  end

  defp first_release_changeset(product, firmware, created_by_user) do
    change(%DeploymentRelease{})
    |> put_assoc(:firmware, firmware)
    |> put_assoc(:created_by, created_by_user)
    |> put_change(:number, 1)
    |> validate_required([:firmware])
    |> validate_change(:created_by, fn :created_by, created_by_assoc ->
      created_by = created_by_assoc.data

      User
      |> join(:inner, [u], o in assoc(u, :orgs))
      |> join(:inner, [_, o], p in assoc(o, :products))
      |> where([u], u.id == ^created_by.id)
      |> where([_, _, p], p.id == ^product.id)
      |> Repo.one()
      |> case do
        nil -> [created_by_id: "invalid associated user"]
        _user -> []
      end
    end)
  end

  defp validate_firmware(changeset, product) do
    validate_change(changeset, :firmware, fn :firmware, firmware ->
      if not is_nil(firmware) && firmware.product_id != product.id do
        [firmware: "invalid firmware selected"]
      else
        []
      end
    end)
  end

  defp validate_platform(changeset) do
    firmware = get_field(changeset, :firmware)

    validate_change(changeset, :platform, fn :platform, platform ->
      if not is_nil(firmware) && platform != firmware.platform do
        [platform: "platform doesn't match firmwares platform"]
      else
        []
      end
    end)
  end

  defp validate_architecture(changeset) do
    firmware = get_field(changeset, :firmware)

    validate_change(changeset, :architecture, fn :architecture, architecture ->
      if not is_nil(firmware) && architecture != firmware.architecture do
        [architecture: "architecture doesn't match firmwares platform"]
      else
        []
      end
    end)
  end

  defp maybe_add_architecture(changeset) do
    firmware = get_field(changeset, :firmware)
    architecture = get_field(changeset, :architecture)

    cond do
      is_nil(firmware) -> changeset
      is_nil(architecture) -> put_change(changeset, :architecture, firmware.architecture)
      true -> changeset
    end
  end

  defp maybe_add_platform(changeset) do
    firmware = get_field(changeset, :firmware)
    platform = get_field(changeset, :platform)

    cond do
      is_nil(firmware) -> changeset
      is_nil(platform) -> put_change(changeset, :platform, firmware.platform)
      true -> changeset
    end
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
      :priority_queue_enabled,
      :priority_queue_firmware_version_threshold,
      :release_network_interfaces,
      :release_tags
    ])
    |> cast_and_validate_numeric_fields(params)
    |> cast_embed(:conditions, required: true, with: &conditions_changeset/2)
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

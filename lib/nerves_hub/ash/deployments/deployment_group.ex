defmodule NervesHub.Ash.Deployments.DeploymentGroup do
  use Ash.Resource,
    domain: NervesHub.Ash.Deployments,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  alias NervesHub.ManagedDeployments

  postgres do
    table "deployments"
    repo NervesHub.Repo
  end

  json_api do
    type "deployment-group"
    derive_filter? false

    routes do
      base "/deployment-groups"

      index :read
      index :list_by_product, route: "/by-product/:product_id"
      get :read, route: "/:id"
      get :get_by_product_and_name, route: "/by-product/:product_id/by-name/:name"
      post :create
      patch :update
      delete :destroy
    end
  end

  graphql do
    encode_primary_key? false
    type :deployment_group

    queries do
      get :get_deployment_group, :read
      list :list_deployment_groups, :read
      list :list_deployment_groups_by_product, :list_by_product
      get :get_deployment_group_by_product_and_name, :get_by_product_and_name
    end

    mutations do
      create :create_deployment_group, :create
      update :update_deployment_group, :update
      destroy :destroy_deployment_group, :destroy
    end
  end

  attributes do
    integer_primary_key :id

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :firmware_id, :integer, public?: true
    attribute :archive_id, :integer, public?: true
    attribute :product_id, :integer, allow_nil?: false, public?: true
    attribute :org_id, :integer, allow_nil?: false, public?: true
    attribute :is_active, :boolean, default: false, public?: true
    attribute :healthy, :boolean, default: true, public?: true
    attribute :delta_updatable, :boolean, default: true, public?: true
    attribute :concurrent_updates, :integer, default: 10, public?: true
    attribute :penalty_timeout_minutes, :integer, default: 1440, public?: true
    attribute :device_failure_threshold, :integer, default: 3, public?: true
    attribute :device_failure_rate_seconds, :integer, default: 180, public?: true
    attribute :device_failure_rate_amount, :integer, default: 5, public?: true
    attribute :failure_threshold, :integer, default: 50, public?: true
    attribute :inflight_update_expiration_minutes, :integer, default: 60, public?: true
    attribute :connecting_code, :string, public?: true
    attribute :total_updating_devices, :integer, default: 0, public?: true
    attribute :current_updated_devices, :integer, default: 0, public?: true
    attribute :queue_management, :atom, constraints: [one_of: [:FIFO, :LIFO]], default: :FIFO, public?: true
    attribute :status, :atom, constraints: [one_of: [:ready, :preparing, :deltas_failed, :unknown_error]], default: :ready, public?: true
    attribute :priority_queue_enabled, :boolean, default: false, public?: true
    attribute :priority_queue_concurrent_updates, :integer, default: 5, public?: true
    attribute :priority_queue_firmware_version_threshold, :string, public?: true
    attribute :release_network_interfaces, {:array, :atom}, public?: true
    attribute :release_tags, {:array, :string}, public?: true
    attribute :conditions, :map, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :org, NervesHub.Ash.Accounts.Org do
      public? true
      source_attribute :org_id
      destination_attribute :id
    end

    belongs_to :product, NervesHub.Ash.Products.Product do
      public? true
      source_attribute :product_id
      destination_attribute :id
    end

    belongs_to :firmware, NervesHub.Ash.Firmwares.Firmware do
      public? true
      source_attribute :firmware_id
      destination_attribute :id
    end

    belongs_to :archive, NervesHub.Ash.Archives.Archive do
      public? true
      source_attribute :archive_id
      destination_attribute :id
    end

    has_many :devices, NervesHub.Ash.Devices.Device do
      public? true
      source_attribute :id
      destination_attribute :deployment_id
    end

    has_many :inflight_updates, NervesHub.Ash.Devices.InflightUpdate do
      public? true
      source_attribute :id
      destination_attribute :deployment_id
    end

    has_many :deployment_releases, NervesHub.Ash.Deployments.DeploymentRelease do
      public? true
      source_attribute :id
      destination_attribute :deployment_group_id
    end

    has_many :inflight_deployment_checks, NervesHub.Ash.Deployments.InflightDeploymentCheck do
      public? true
      source_attribute :id
      destination_attribute :deployment_id
    end
  end

  actions do
    defaults [:read]

    read :list_by_product do
      argument :product_id, :integer, allow_nil?: false

      filter expr(product_id == ^arg(:product_id))
    end

    read :get_by_product_and_name do
      argument :product_id, :integer, allow_nil?: false
      argument :name, :string, allow_nil?: false

      filter expr(product_id == ^arg(:product_id) and name == ^arg(:name))
    end

    read :list_by_product_and_platform do
      argument :product_id, :integer, allow_nil?: false
      argument :platform, :string, allow_nil?: false

      filter expr(product_id == ^arg(:product_id))
      # Note: platform filtering requires joining through firmware - handled at query level
    end

    action :up_to_date_count, :integer do
      argument :deployment_group_id, :integer, allow_nil?: false

      run fn input, _context ->
        dg = NervesHub.Repo.get!(NervesHub.ManagedDeployments.DeploymentGroup, input.arguments.deployment_group_id)
        dg = NervesHub.Repo.preload(dg, current_release: :firmware)
        {:ok, NervesHub.Devices.up_to_date_count(dg)}
      end
    end

    action :updating_count, :integer do
      argument :deployment_group_id, :integer, allow_nil?: false

      run fn input, _context ->
        dg = NervesHub.Repo.get!(NervesHub.ManagedDeployments.DeploymentGroup, input.arguments.deployment_group_id)
        {:ok, NervesHub.Devices.updating_count(dg)}
      end
    end

    action :waiting_for_update_count, :integer do
      argument :deployment_group_id, :integer, allow_nil?: false

      run fn input, _context ->
        dg = NervesHub.Repo.get!(NervesHub.ManagedDeployments.DeploymentGroup, input.arguments.deployment_group_id)
        dg = NervesHub.Repo.preload(dg, current_release: :firmware)
        {:ok, NervesHub.Devices.waiting_for_update_count(dg)}
      end
    end

    action :get_device_count, :integer do
      argument :deployment_group_id, :integer, allow_nil?: false

      run fn input, _context ->
        dg = %NervesHub.ManagedDeployments.DeploymentGroup{id: input.arguments.deployment_group_id}
        {:ok, ManagedDeployments.get_device_count(dg)}
      end
    end

    read :list_active do
      filter expr(is_active == true)
    end

    create :create do
      accept [
        :name,
        :firmware_id,
        :product_id,
        :org_id,
        :is_active,
        :delta_updatable,
        :concurrent_updates,
        :penalty_timeout_minutes
      ]
    end

    update :update do
      primary? true
      accept [
        :name,
        :firmware_id,
        :is_active,
        :delta_updatable,
        :concurrent_updates,
        :penalty_timeout_minutes,
        :device_failure_threshold,
        :device_failure_rate_seconds,
        :device_failure_rate_amount,
        :failure_threshold,
        :inflight_update_expiration_minutes
      ]
    end

    destroy :destroy do
      primary? true
      manual fn changeset, _context ->
        ecto_dg = NervesHub.Repo.get!(NervesHub.ManagedDeployments.DeploymentGroup, changeset.data.id)

        case ManagedDeployments.delete_deployment_group(ecto_dg) do
          {:ok, _} -> {:ok, changeset.data}
          {:error, error} -> {:error, error}
        end
      end
    end
  end

  code_interface do
    define :read
    define :get, action: :read, get_by: [:id], not_found_error?: true
    define :list_by_product, args: [:product_id]
    define :get_by_product_and_name, args: [:product_id, :name], get?: true
    define :list_by_product_and_platform, args: [:product_id, :platform]
    define :up_to_date_count, args: [:deployment_group_id]
    define :updating_count, args: [:deployment_group_id]
    define :waiting_for_update_count, args: [:deployment_group_id]
    define :get_device_count, args: [:deployment_group_id]
    define :list_active
    define :create
    define :update
    define :destroy
  end
end

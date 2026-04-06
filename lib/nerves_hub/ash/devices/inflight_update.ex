defmodule NervesHub.Ash.Devices.InflightUpdate do
  use Ash.Resource,
    domain: NervesHub.Ash.Devices,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  postgres do
    table "inflight_updates"
    repo NervesHub.Repo
  end

  json_api do
    type "inflight-update"
    derive_filter? false

    routes do
      base "/inflight-updates"

      index :read
      index :list_by_device, route: "/by-device/:device_id"
      index :list_by_deployment, route: "/by-deployment/:deployment_id"
      get :read, route: "/:id"
    end
  end

  graphql do
    encode_primary_key? false
    type :inflight_update

    queries do
      get :get_inflight_update, :read
      list :list_inflight_updates, :read
      list :list_inflight_updates_by_device, :list_by_device
      list :list_inflight_updates_by_deployment, :list_by_deployment
    end
  end

  attributes do
    integer_primary_key :id

    attribute :device_id, :integer, allow_nil?: false, public?: true
    attribute :deployment_id, :integer, allow_nil?: false, public?: true
    attribute :firmware_id, :integer, allow_nil?: false, public?: true
    attribute :firmware_uuid, :uuid, public?: true
    attribute :status, :string, default: "pending", public?: true
    attribute :expires_at, :utc_datetime, public?: true
    attribute :priority_queue, :boolean, default: false, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :device, NervesHub.Ash.Devices.Device do
      public? true
      source_attribute :device_id
      destination_attribute :id
    end

    belongs_to :deployment_group, NervesHub.Ash.Deployments.DeploymentGroup do
      public? true
      source_attribute :deployment_id
      destination_attribute :id
    end

    belongs_to :firmware, NervesHub.Ash.Firmwares.Firmware do
      public? true
      source_attribute :firmware_id
      destination_attribute :id
    end
  end

  actions do
    defaults [:read]

    read :list_by_device do
      argument :device_id, :integer, allow_nil?: false

      filter expr(device_id == ^arg(:device_id))
    end

    read :list_by_deployment do
      argument :deployment_id, :integer, allow_nil?: false

      filter expr(deployment_id == ^arg(:deployment_id))
    end

    action :count_by_deployment, :integer do
      argument :deployment_id, :integer, allow_nil?: false

      run fn input, _context ->
        dg = %NervesHub.ManagedDeployments.DeploymentGroup{id: input.arguments.deployment_id}
        {:ok, NervesHub.Devices.count_inflight_updates_for(dg)}
      end
    end

    action :count_priority_by_deployment, :integer do
      argument :deployment_id, :integer, allow_nil?: false

      run fn input, _context ->
        dg = %NervesHub.ManagedDeployments.DeploymentGroup{id: input.arguments.deployment_id}
        {:ok, NervesHub.Devices.count_inflight_priority_updates_for(dg)}
      end
    end

    create :create do
      accept [:device_id, :deployment_id, :firmware_id, :firmware_uuid, :expires_at, :priority_queue]
    end

    update :update_status do
      accept [:status]
    end

    destroy :destroy do
      primary? true
    end
  end

  code_interface do
    define :read
    define :get, action: :read, get_by: [:id], not_found_error?: true
    define :list_by_device, args: [:device_id]
    define :list_by_deployment, args: [:deployment_id]
    define :count_by_deployment, args: [:deployment_id]
    define :count_priority_by_deployment, args: [:deployment_id]
    define :create
    define :update_status
    define :destroy
  end
end

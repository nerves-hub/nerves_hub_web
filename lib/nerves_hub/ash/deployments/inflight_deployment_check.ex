defmodule NervesHub.Ash.Deployments.InflightDeploymentCheck do
  use Ash.Resource,
    domain: NervesHub.Ash.Deployments,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  postgres do
    table "inflight_deployment_checks"
    repo NervesHub.Repo
  end

  json_api do
    type "inflight-deployment-check"
    derive_filter? false

    routes do
      base "/inflight-deployment-checks"

      index :read
      index :list_by_deployment, route: "/by-deployment/:deployment_id"
      get :read, route: "/:id"
    end
  end

  graphql do
    encode_primary_key? false
    type :inflight_deployment_check

    queries do
      get :get_inflight_deployment_check, :read
      list :list_inflight_deployment_checks, :read
      list :list_inflight_deployment_checks_by_deployment, :list_by_deployment
    end
  end

  attributes do
    integer_primary_key :id

    attribute :device_id, :integer, allow_nil?: false, public?: true
    attribute :deployment_id, :integer, allow_nil?: false, public?: true

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
  end

  actions do
    defaults [:read]

    read :list_by_deployment do
      argument :deployment_id, :integer, allow_nil?: false

      filter expr(deployment_id == ^arg(:deployment_id))
    end

    create :create do
      accept [:device_id, :deployment_id]
    end

    destroy :destroy do
      primary? true
    end
  end

  code_interface do
    define :read
    define :get, action: :read, get_by: [:id], not_found_error?: true
    define :list_by_deployment, args: [:deployment_id]
    define :create
    define :destroy
  end
end

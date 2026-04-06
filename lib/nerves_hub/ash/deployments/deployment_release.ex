defmodule NervesHub.Ash.Deployments.DeploymentRelease do
  use Ash.Resource,
    domain: NervesHub.Ash.Deployments,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  postgres do
    table "deployment_releases"
    repo NervesHub.Repo
  end

  json_api do
    type "deployment-release"
    derive_filter? false

    routes do
      base "/deployment-releases"

      index :read
      index :list_by_deployment_group, route: "/by-deployment-group/:deployment_group_id"
      get :read, route: "/:id"
    end
  end

  graphql do
    encode_primary_key? false
    type :deployment_release

    queries do
      get :get_deployment_release, :read
      list :list_deployment_releases, :read
      list :list_deployment_releases_by_deployment_group, :list_by_deployment_group
    end
  end

  attributes do
    integer_primary_key :id

    attribute :deployment_group_id, :integer, allow_nil?: false, public?: true
    attribute :firmware_id, :integer, allow_nil?: false, public?: true
    attribute :archive_id, :integer, public?: true
    attribute :created_by_id, :integer, allow_nil?: false, public?: true
    attribute :number, :integer, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :deployment_group, NervesHub.Ash.Deployments.DeploymentGroup do
      public? true
      source_attribute :deployment_group_id
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

    belongs_to :user, NervesHub.Ash.Accounts.User do
      public? true
      source_attribute :created_by_id
      destination_attribute :id
    end
  end

  actions do
    defaults [:read]

    read :list_by_deployment_group do
      argument :deployment_group_id, :integer, allow_nil?: false

      filter expr(deployment_group_id == ^arg(:deployment_group_id))
    end

    create :create do
      accept [:deployment_group_id, :firmware_id, :archive_id, :created_by_id, :number]
    end
  end

  code_interface do
    define :read
    define :get, action: :read, get_by: [:id], not_found_error?: true
    define :list_by_deployment_group, args: [:deployment_group_id]
    define :create
  end
end

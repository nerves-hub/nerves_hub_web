defmodule NervesHub.Ash.AuditLogs.AuditLog do
  use Ash.Resource,
    domain: NervesHub.Ash.AuditLogs,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  postgres do
    table "audit_logs"
    repo NervesHub.Repo
  end

  json_api do
    type "audit-log"
    derive_filter? false

    routes do
      base "/audit-logs"

      index :read
      index :list_by_org, route: "/by-org/:org_id"
    end
  end

  graphql do
    encode_primary_key? false
    type :audit_log

    queries do
      get :get_audit_log, :read
      list :list_audit_logs, :read
      list :list_audit_logs_by_org, :list_by_org
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :org_id, :integer, allow_nil?: false, public?: true
    attribute :actor_id, :integer, public?: true
    attribute :actor_type, :string, public?: true
    attribute :description, :string, public?: true
    attribute :params, :map, public?: true
    attribute :resource_id, :integer, public?: true
    attribute :resource_type, :string, public?: true
    attribute :reference_id, :string, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :org, NervesHub.Ash.Accounts.Org do
      public? true
      source_attribute :org_id
      destination_attribute :id
    end
  end

  actions do
    defaults [:read]

    read :list_by_org do
      argument :org_id, :integer, allow_nil?: false

      filter expr(org_id == ^arg(:org_id))
    end

    read :list_by_resource do
      argument :resource_type, :string, allow_nil?: false
      argument :resource_id, :integer, allow_nil?: false

      filter expr(resource_type == ^arg(:resource_type) and resource_id == ^arg(:resource_id))
    end

    read :list_by_actor do
      argument :actor_type, :string, allow_nil?: false
      argument :actor_id, :integer, allow_nil?: false

      filter expr(actor_type == ^arg(:actor_type) and actor_id == ^arg(:actor_id))
    end

    create :create do
      primary? true
      accept [:org_id, :actor_id, :actor_type, :description, :params, :resource_id, :resource_type, :reference_id]
    end
  end

  code_interface do
    define :read
    define :get, action: :read, get_by: [:id], not_found_error?: true
    define :list_by_org, args: [:org_id]
    define :list_by_resource, args: [:resource_type, :resource_id]
    define :list_by_actor, args: [:actor_type, :actor_id]
    define :create
  end
end

defmodule NervesHub.Ash.Accounts.OrgMetric do
  use Ash.Resource,
    domain: NervesHub.Ash.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  postgres do
    table "org_metrics"
    repo NervesHub.Repo
  end

  json_api do
    type "org-metric"
    derive_filter? false

    routes do
      base "/org-metrics"

      index :read
      get :read
      post :create
    end
  end

  graphql do
    encode_primary_key? false
    type :org_metric

    queries do
      get :get_org_metric, :read
      list :list_org_metrics, :read
    end

    mutations do
      create :create_org_metric, :create
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :org_id, :integer, allow_nil?: false, public?: true
    attribute :devices, :integer, public?: true
    attribute :bytes_stored, :integer, public?: true
    attribute :timestamp, :utc_datetime, public?: true
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

    create :create do
      accept [:org_id, :devices, :bytes_stored, :timestamp]
    end
  end

  code_interface do
    define :read
    define :get, action: :read, get_by: [:id], not_found_error?: true
    define :create
  end
end

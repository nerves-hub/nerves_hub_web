defmodule NervesHub.Ash.Products.Notification do
  use Ash.Resource,
    domain: NervesHub.Ash.Products,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  postgres do
    table "product_notifications"
    repo NervesHub.Repo
  end

  json_api do
    type "product-notification"
    derive_filter? false

    routes do
      base "/product-notifications"

      index :read
      index :list_by_product, route: "/by-product/:product_id"
      get :read, route: "/:id"
    end
  end

  graphql do
    encode_primary_key? false
    type :product_notification

    queries do
      get :get_product_notification, :read
      list :list_product_notifications, :read
      list :list_product_notifications_by_product, :list_by_product
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :product_id, :integer, allow_nil?: false, public?: true
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :message, :string, allow_nil?: false, public?: true
    attribute :metadata, :map, public?: true
    attribute :level, :atom, allow_nil?: false, public?: true, constraints: [one_of: [:info, :warning, :error]]
    attribute :event_key, :string, allow_nil?: false, public?: true
    attribute :last_occurred_at, :utc_datetime, public?: true
    attribute :occurrence_count, :integer, default: 1, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :product, NervesHub.Ash.Products.Product do
      public? true
      source_attribute :product_id
      destination_attribute :id
    end
  end

  actions do
    defaults [:read]

    read :list_by_product do
      argument :product_id, :integer, allow_nil?: false

      filter expr(product_id == ^arg(:product_id))
    end

    create :create do
      accept [:product_id, :title, :message, :metadata, :level, :event_key, :last_occurred_at, :occurrence_count]
    end

    update :update do
      accept [:last_occurred_at, :occurrence_count]
    end
  end

  code_interface do
    define :read
    define :get, action: :read, get_by: [:id], not_found_error?: true
    define :list_by_product, args: [:product_id]
    define :create
    define :update
  end
end

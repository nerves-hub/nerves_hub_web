defmodule NervesHub.Ash.Devices.JITP do
  use Ash.Resource,
    domain: NervesHub.Ash.Devices,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  postgres do
    table "jitp"
    repo NervesHub.Repo
  end

  json_api do
    type "jitp"
    derive_filter? false

    routes do
      base "/jitp"

      index :read
      index :list_by_product, route: "/by-product/:product_id"
      get :read, route: "/:id"
      post :create
      patch :update
      delete :destroy
    end
  end

  graphql do
    encode_primary_key? false
    type :jitp

    queries do
      get :get_jitp, :read
      list :list_jitp, :read
      list :list_jitp_by_product, :list_by_product
    end

    mutations do
      create :create_jitp, :create
      update :update_jitp, :update
      destroy :destroy_jitp, :destroy
    end
  end

  attributes do
    integer_primary_key :id

    attribute :product_id, :integer, allow_nil?: false, public?: true
    attribute :tags, {:array, :string}, public?: true
    attribute :description, :string, public?: true

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
      accept [:product_id, :tags, :description]
    end

    update :update do
      accept [:tags, :description]
    end

    destroy :destroy do
      primary? true
    end
  end

  code_interface do
    define :read
    define :get, action: :read, get_by: [:id], not_found_error?: true
    define :list_by_product, args: [:product_id]
    define :create
    define :update
    define :destroy
  end
end

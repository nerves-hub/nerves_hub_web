defmodule NervesHub.Ash.Products.SharedSecretAuth do
  use Ash.Resource,
    domain: NervesHub.Ash.Products,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  postgres do
    table "product_shared_secret_auth"
    repo NervesHub.Repo
  end

  json_api do
    type "product-shared-secret-auth"
    derive_filter? false

    routes do
      base "/product-shared-secret-auths"

      index :read
      index :list_by_product, route: "/by-product/:product_id"
      get :read, route: "/:id"
    end
  end

  graphql do
    encode_primary_key? false
    type :product_shared_secret_auth

    queries do
      get :get_product_shared_secret_auth, :read
      list :list_product_shared_secret_auths, :read
      list :list_product_shared_secret_auths_by_product, :list_by_product
    end
  end

  attributes do
    integer_primary_key :id

    attribute :product_id, :integer, allow_nil?: false, public?: true
    # key and secret are sensitive - not exposed via API
    attribute :key, :string, public?: false
    attribute :secret, :string, public?: false
    attribute :deactivated_at, :utc_datetime, public?: true

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

    read :get_by_product_and_id do
      argument :product_id, :integer, allow_nil?: false
      argument :auth_id, :integer, allow_nil?: false

      filter expr(product_id == ^arg(:product_id) and id == ^arg(:auth_id))
    end

    read :get_by_key do
      argument :key, :string, allow_nil?: false

      filter expr(key == ^arg(:key) and is_nil(deactivated_at))
    end

    create :create do
      argument :product_id, :integer, allow_nil?: false

      manual fn changeset, _context ->
        product_id = changeset.arguments.product_id
        ecto_product = NervesHub.Repo.get!(NervesHub.Products.Product, product_id)

        case NervesHub.Products.create_shared_secret_auth(ecto_product) do
          {:ok, ecto_auth} ->
            ash_fields = [:id, :product_id, :key, :secret, :deactivated_at, :inserted_at, :updated_at]
            {:ok, struct!(NervesHub.Ash.Products.SharedSecretAuth, Map.take(ecto_auth, ash_fields))}

          {:error, error} ->
            {:error, error}
        end
      end
    end

    update :deactivate do
      accept []

      manual fn changeset, _context ->
        ecto_auth = NervesHub.Repo.get!(NervesHub.Products.SharedSecretAuth, changeset.data.id)

        case NervesHub.Products.SharedSecretAuth.deactivate_changeset(ecto_auth) |> NervesHub.Repo.update() do
          {:ok, updated} ->
            ash_fields = [:id, :product_id, :key, :secret, :deactivated_at, :inserted_at, :updated_at]
            {:ok, struct!(NervesHub.Ash.Products.SharedSecretAuth, Map.take(updated, ash_fields))}

          {:error, error} ->
            {:error, error}
        end
      end
    end

    destroy :destroy do
      primary? true
    end
  end

  code_interface do
    define :read
    define :get, action: :read, get_by: [:id], not_found_error?: true
    define :list_by_product, args: [:product_id]
    define :get_by_product_and_id, args: [:product_id, :id], get?: true
    define :get_by_key, args: [:key], get?: true
    define :create
    define :deactivate
    define :destroy
  end
end

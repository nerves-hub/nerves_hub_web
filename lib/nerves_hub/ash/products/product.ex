defmodule NervesHub.Ash.Products.Product do
  use Ash.Resource,
    domain: NervesHub.Ash.Products,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  alias NervesHub.Products

  postgres do
    table "products"
    repo NervesHub.Repo
  end

  json_api do
    type "product"
    derive_filter? false

    routes do
      base "/products"

      index :read
      index :list_by_org, route: "/by-org/:org_id"
      get :read, route: "/:id"
      get :get_by_org_and_name, route: "/by-org/:org_id/by-name/:name"
      post :create
      delete :destroy
    end
  end

  graphql do
    encode_primary_key? false
    type :product

    queries do
      get :get_product, :read
      list :list_products, :read
      list :list_products_by_org, :list_by_org
      get :get_product_by_org_and_name, :get_by_org_and_name
    end

    mutations do
      create :create_product, :create
      destroy :destroy_product, :destroy
    end
  end

  attributes do
    integer_primary_key :id

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :org_id, :integer, allow_nil?: false, public?: true
    attribute :deleted_at, :utc_datetime, public?: true
    attribute :extensions, :map, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :org, NervesHub.Ash.Accounts.Org do
      public? true
      source_attribute :org_id
      destination_attribute :id
    end

    has_many :devices, NervesHub.Ash.Devices.Device do
      public? true
      source_attribute :id
      destination_attribute :product_id
    end

    has_many :firmwares, NervesHub.Ash.Firmwares.Firmware do
      public? true
      source_attribute :id
      destination_attribute :product_id
    end

    has_many :deployment_groups, NervesHub.Ash.Deployments.DeploymentGroup do
      public? true
      source_attribute :id
      destination_attribute :product_id
    end

    has_many :scripts, NervesHub.Ash.Scripts.Script do
      public? true
      source_attribute :id
      destination_attribute :product_id
    end

    has_many :notifications, NervesHub.Ash.Products.Notification do
      public? true
      source_attribute :id
      destination_attribute :product_id
    end

    has_many :shared_secret_auths, NervesHub.Ash.Products.SharedSecretAuth do
      public? true
      source_attribute :id
      destination_attribute :product_id
    end

    has_many :jitp, NervesHub.Ash.Devices.JITP do
      public? true
      source_attribute :id
      destination_attribute :product_id
    end

    has_many :archives, NervesHub.Ash.Archives.Archive do
      public? true
      source_attribute :id
      destination_attribute :product_id
    end
  end

  actions do
    defaults [:read]

    read :list_by_org do
      argument :org_id, :integer, allow_nil?: false

      filter expr(org_id == ^arg(:org_id) and is_nil(deleted_at))
    end

    read :get_by_org_and_name do
      argument :org_id, :integer, allow_nil?: false
      argument :name, :string, allow_nil?: false

      filter expr(org_id == ^arg(:org_id) and name == ^arg(:name) and is_nil(deleted_at))
    end

    action :count_by_org, :integer do
      argument :org_id, :integer, allow_nil?: false

      run fn input, _context ->
        import Ecto.Query

        count =
          NervesHub.Products.Product
          |> where([p], p.org_id == ^input.arguments.org_id)
          |> where([p], is_nil(p.deleted_at))
          |> NervesHub.Repo.aggregate(:count)

        {:ok, count}
      end
    end

    create :create do
      primary? true
      accept [:name, :org_id]
    end

    update :update do
      primary? true
      accept [:name]

      manual fn changeset, _context ->
        ecto_product = NervesHub.Repo.get!(NervesHub.Products.Product, changeset.data.id)
        params = %{"name" => Ash.Changeset.get_attribute(changeset, :name)}

        case NervesHub.Products.Product.changeset(ecto_product, params) |> NervesHub.Repo.update() do
          {:ok, updated} ->
            ash_fields = [:id, :name, :org_id, :deleted_at, :extensions, :inserted_at, :updated_at]
            {:ok, struct!(NervesHub.Ash.Products.Product, Map.take(updated, ash_fields))}

          {:error, error} ->
            {:error, error}
        end
      end
    end

    update :enable_extension do
      accept []
      argument :extension, :string, allow_nil?: false

      manual fn changeset, _context ->
        extension = changeset.arguments.extension
        ecto_product = NervesHub.Repo.get!(NervesHub.Products.Product, changeset.data.id)

        case Products.enable_extension_setting(ecto_product, extension) do
          {:ok, updated} ->
            ash_fields = [:id, :name, :org_id, :deleted_at, :inserted_at, :updated_at]
            attrs = Map.take(updated, ash_fields)
            attrs = Map.put(attrs, :extensions, extensions_to_map(updated.extensions))
            {:ok, struct!(NervesHub.Ash.Products.Product, attrs)}

          {:error, error} ->
            {:error, error}
        end
      end
    end

    update :disable_extension do
      accept []
      argument :extension, :string, allow_nil?: false

      manual fn changeset, _context ->
        extension = changeset.arguments.extension
        ecto_product = NervesHub.Repo.get!(NervesHub.Products.Product, changeset.data.id)

        case Products.disable_extension_setting(ecto_product, extension) do
          {:ok, updated} ->
            ash_fields = [:id, :name, :org_id, :deleted_at, :inserted_at, :updated_at]
            attrs = Map.take(updated, ash_fields)
            attrs = Map.put(attrs, :extensions, extensions_to_map(updated.extensions))
            {:ok, struct!(NervesHub.Ash.Products.Product, attrs)}

          {:error, error} ->
            {:error, error}
        end
      end
    end

    destroy :destroy do
      primary? true
      manual fn changeset, _context ->
        ecto_product = NervesHub.Repo.get!(NervesHub.Products.Product, changeset.data.id)

        case Products.delete_product(ecto_product) do
          {:ok, _} -> {:ok, changeset.data}
          {:error, error} -> {:error, error}
        end
      end
    end
  end

  code_interface do
    define :read
    define :get, action: :read, get_by: [:id], not_found_error?: true
    define :list_by_org, args: [:org_id]
    define :get_by_org_and_name, args: [:org_id, :name], get?: true
    define :count_by_org, args: [:org_id]
    define :create
    define :update
    define :enable_extension, args: [:extension]
    define :disable_extension, args: [:extension]
    define :destroy
  end

  defp extensions_to_map(nil), do: %{}

  defp extensions_to_map(%{} = ext) do
    ext
    |> Map.from_struct()
    |> Map.delete(:__meta__)
    |> Map.delete(:id)
    |> Enum.into(%{}, fn {k, v} -> {Atom.to_string(k), v} end)
  end
end

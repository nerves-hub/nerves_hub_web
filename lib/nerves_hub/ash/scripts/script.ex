defmodule NervesHub.Ash.Scripts.Script do
  use Ash.Resource,
    domain: NervesHub.Ash.Scripts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  alias NervesHub.Ash.Accounts.User
  alias NervesHub.Ash.Products.Product
  alias NervesHub.Scripts.Script

  postgres do
    table("scripts")
    repo(NervesHub.Repo)
  end

  json_api do
    type("script")
    derive_filter?(false)

    routes do
      base("/scripts")

      index(:read)
      index(:list_by_product, route: "/by-product/:product_id")
      get(:read, route: "/:id")
      get(:get_by_product_and_name, route: "/by-product/:product_id/by-name/:name")
      post(:create)
      patch(:update)
      delete(:destroy)
    end
  end

  graphql do
    encode_primary_key? false
    type(:script)

    queries do
      get(:get_script, :read)
      list(:list_scripts, :read)
      list(:list_scripts_by_product, :list_by_product)
      get(:get_script_by_product_and_name, :get_by_product_and_name)
    end

    mutations do
      create(:create_script, :create)
      update(:update_script, :update)
      destroy(:destroy_script, :destroy)
    end
  end

  attributes do
    integer_primary_key(:id)

    attribute(:name, :string, allow_nil?: false, public?: true)
    attribute(:text, :string, public?: true)
    attribute(:tags, {:array, :string}, public?: true)
    attribute(:product_id, :integer, allow_nil?: false, public?: true)
    attribute(:created_by_id, :integer, public?: true)
    attribute(:last_updated_by_id, :integer, public?: true)

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :product, Product do
      public?(true)
      source_attribute(:product_id)
      destination_attribute(:id)
    end

    belongs_to :created_by, User do
      public?(true)
      source_attribute(:created_by_id)
      destination_attribute(:id)
    end

    belongs_to :last_updated_by, User do
      public?(true)
      source_attribute(:last_updated_by_id)
      destination_attribute(:id)
    end
  end

  actions do
    defaults([:read])

    read :list_by_product do
      argument(:product_id, :integer, allow_nil?: false)

      filter(expr(product_id == ^arg(:product_id)))
    end

    read :get_by_product_and_name do
      argument(:product_id, :integer, allow_nil?: false)
      argument(:name, :string, allow_nil?: false)

      filter(expr(product_id == ^arg(:product_id) and name == ^arg(:name)))
    end

    read :get_by_product_and_id do
      argument(:product_id, :integer, allow_nil?: false)
      argument(:script_id, :integer, allow_nil?: false)

      filter(expr(product_id == ^arg(:product_id) and id == ^arg(:script_id)))
    end

    action :count_by_product, :integer do
      argument :product_id, :integer, allow_nil?: false

      run fn input, _context ->
        import Ecto.Query

        count =
          Script
          |> where([s], s.product_id == ^input.arguments.product_id)
          |> NervesHub.Repo.aggregate(:count)

        {:ok, count}
      end
    end

    create :create do
      primary? true
      accept([:name, :text, :product_id, :created_by_id, :last_updated_by_id])
    end

    update :update do
      primary? true
      accept([:name, :text, :last_updated_by_id])
    end

    destroy :destroy do
      primary? true
      manual(fn changeset, _context ->
        ecto_script = NervesHub.Repo.get!(Script, changeset.data.id)

        case NervesHub.Repo.delete(ecto_script) do
          {:ok, _} -> {:ok, changeset.data}
          {:error, error} -> {:error, error}
        end
      end)
    end
  end

  code_interface do
    define :read
    define :get, action: :read, get_by: [:id], not_found_error?: true
    define :list_by_product, args: [:product_id]
    define :get_by_product_and_name, args: [:product_id, :name], get?: true
    define :get_by_product_and_id, args: [:product_id, :script_id], get?: true
    define :count_by_product, args: [:product_id]
    define :create
    define :update
    define :destroy
  end
end

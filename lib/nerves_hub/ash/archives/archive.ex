defmodule NervesHub.Ash.Archives.Archive do
  use Ash.Resource,
    domain: NervesHub.Ash.Archives,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  postgres do
    table "archives"
    repo NervesHub.Repo
  end

  json_api do
    type "archive"
    derive_filter? false

    routes do
      base "/archives"

      index :read
      index :list_by_product, route: "/by-product/:product_id"
      get :read, route: "/:id"
    end
  end

  graphql do
    encode_primary_key? false
    type :archive

    queries do
      get :get_archive, :read
      list :list_archives, :read
      list :list_archives_by_product, :list_by_product
    end
  end

  attributes do
    integer_primary_key :id

    attribute :product_id, :integer, allow_nil?: false, public?: true
    attribute :org_key_id, :integer, public?: true
    attribute :size, :integer, public?: true
    attribute :architecture, :string, public?: true
    attribute :author, :string, public?: true
    attribute :description, :string, public?: true
    attribute :misc, :string, public?: true
    attribute :platform, :string, public?: true
    attribute :uuid, :uuid, public?: true
    attribute :version, :string, public?: true
    attribute :vcs_identifier, :string, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :product, NervesHub.Ash.Products.Product do
      public? true
      source_attribute :product_id
      destination_attribute :id
    end

    belongs_to :org_key, NervesHub.Ash.Accounts.OrgKey do
      public? true
      source_attribute :org_key_id
      destination_attribute :id
    end
  end

  actions do
    defaults [:read]

    read :list_by_product do
      argument :product_id, :integer, allow_nil?: false

      filter expr(product_id == ^arg(:product_id))
    end

    read :get_by_product_and_uuid do
      argument :product_id, :integer, allow_nil?: false
      argument :uuid, :string, allow_nil?: false

      filter expr(product_id == ^arg(:product_id) and uuid == ^arg(:uuid))
    end

    read :get_by_product_and_id do
      argument :product_id, :integer, allow_nil?: false
      argument :archive_id, :integer, allow_nil?: false

      filter expr(product_id == ^arg(:product_id) and id == ^arg(:archive_id))
    end

    action :for_deployment_group, :struct do
      argument :deployment_group_id, :integer, allow_nil?: false

      run fn input, _context ->
        {:ok, NervesHub.Archives.archive_for_deployment_group(input.arguments.deployment_group_id)}
      end
    end

    create :create do
      accept [:product_id, :org_key_id, :size, :architecture, :author, :description, :misc, :platform, :uuid, :version, :vcs_identifier]
    end

    destroy :destroy do
      primary? true
      manual fn changeset, _context ->
        ecto_archive = NervesHub.Repo.get!(NervesHub.Archives.Archive, changeset.data.id)

        case NervesHub.Archives.delete_archive(ecto_archive) do
          {:ok, _} -> {:ok, changeset.data}
          {:error, error} -> {:error, error}
        end
      end
    end
  end

  code_interface do
    define :read
    define :get, action: :read, get_by: [:id], not_found_error?: true
    define :list_by_product, args: [:product_id]
    define :get_by_product_and_uuid, args: [:product_id, :uuid], get?: true
    define :get_by_product_and_id, args: [:product_id, :archive_id], get?: true
    define :for_deployment_group, args: [:deployment_group_id]
    define :create
    define :destroy
  end
end

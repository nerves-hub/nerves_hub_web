defmodule NervesHub.Ash.Accounts.OrgKey do
  use Ash.Resource,
    domain: NervesHub.Ash.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  alias NervesHub.Accounts

  postgres do
    table "org_keys"
    repo NervesHub.Repo
  end

  json_api do
    type "org-key"
    derive_filter? false

    routes do
      base "/org-keys"

      index :read
      index :list_by_org, route: "/by-org/:org_id"
      get :get_by_org, route: "/by-org/:org_id/:key_id"
      get :get_by_name, route: "/by-org/:org_id/by-name/:name"
      post :create
      get :read, route: "/:id"
      patch :update
      delete :destroy
    end
  end

  graphql do
    encode_primary_key? false
    type :org_key

    queries do
      get :get_org_key, :read
      list :list_org_keys, :read
      list :list_org_keys_by_org, :list_by_org
      get :get_org_key_by_org, :get_by_org
      get :get_org_key_by_name, :get_by_name
    end

    mutations do
      create :create_org_key, :create
      update :update_org_key, :update
      destroy :destroy_org_key, :destroy
    end
  end

  attributes do
    integer_primary_key :id

    attribute :org_id, :integer, allow_nil?: false, public?: true
    attribute :created_by_id, :integer, public?: true
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :key, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :org, NervesHub.Ash.Accounts.Org do
      public? true
      source_attribute :org_id
      destination_attribute :id
    end

    belongs_to :created_by, NervesHub.Ash.Accounts.User do
      public? true
      source_attribute :created_by_id
      destination_attribute :id
    end

    has_many :firmwares, NervesHub.Ash.Firmwares.Firmware do
      public? true
      source_attribute :id
      destination_attribute :org_key_id
    end
  end

  actions do
    defaults [:read]

    read :list_by_org do
      argument :org_id, :integer, allow_nil?: false

      filter expr(org_id == ^arg(:org_id))
    end

    read :get_by_org do
      argument :org_id, :integer, allow_nil?: false
      argument :key_id, :integer, allow_nil?: false

      filter expr(org_id == ^arg(:org_id) and id == ^arg(:key_id))
    end

    read :get_by_name do
      argument :org_id, :integer, allow_nil?: false
      argument :name, :string, allow_nil?: false

      filter expr(org_id == ^arg(:org_id) and name == ^arg(:name))
    end

    create :create do
      primary? true
      accept [:name, :key, :org_id, :created_by_id]
    end

    update :update do
      accept [:name]
    end

    destroy :destroy do
      primary? true
      manual fn changeset, _context ->
        ecto_org_key = NervesHub.Repo.get!(NervesHub.Accounts.OrgKey, changeset.data.id)

        case Accounts.delete_org_key(ecto_org_key) do
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
    define :get_by_org, args: [:org_id, :key_id], get?: true
    define :get_by_name, args: [:org_id, :name], get?: true
    define :create
    define :update
    define :destroy
  end
end

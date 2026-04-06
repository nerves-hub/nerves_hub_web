defmodule NervesHub.Ash.Accounts.Org do
  use Ash.Resource,
    domain: NervesHub.Ash.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  alias NervesHub.Accounts

  postgres do
    table "orgs"
    repo NervesHub.Repo
  end

  json_api do
    type "org"
    derive_filter? false

    routes do
      base "/orgs"

      index :read
      post :create
      get :read, route: "/:id"
      get :get_by_name, route: "/by-name/:name"
      index :get_for_user, route: "/for-user/:user_id"
      patch :update
      delete :destroy
    end
  end

  graphql do
    encode_primary_key? false
    type :org

    queries do
      get :get_org, :read
      list :list_orgs, :read
      get :get_org_by_name, :get_by_name
      list :list_orgs_for_user, :get_for_user
    end

    mutations do
      create :create_org, :create
      create :create_org_with_user, :create_with_user
      update :update_org, :update
      destroy :destroy_org, :destroy
    end
  end

  attributes do
    integer_primary_key :id

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :audit_log_days_to_keep, :integer, public?: true
    attribute :deleted_at, :utc_datetime, public?: true
    attribute :settings, :map, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :org_keys, NervesHub.Ash.Accounts.OrgKey do
      public? true
      source_attribute :id
      destination_attribute :org_id
    end

    has_many :org_users, NervesHub.Ash.Accounts.OrgUser do
      public? true
      source_attribute :id
      destination_attribute :org_id
    end

    has_many :products, NervesHub.Ash.Products.Product do
      public? true
      source_attribute :id
      destination_attribute :org_id
    end

    has_many :devices, NervesHub.Ash.Devices.Device do
      public? true
      source_attribute :id
      destination_attribute :org_id
    end

    has_many :ca_certificates, NervesHub.Ash.Devices.CACertificate do
      public? true
      source_attribute :id
      destination_attribute :org_id
    end
  end

  actions do
    defaults [:read]

    read :get_by_name do
      argument :name, :string, allow_nil?: false

      filter expr(name == ^arg(:name) and is_nil(deleted_at))
    end

    read :get_for_user do
      argument :user_id, :integer, allow_nil?: false

      manual fn ash_query, _ecto_query, context ->
        user_id = ash_query.arguments.user_id

        import Ecto.Query

        results =
          NervesHub.Accounts.Org
          |> join(:inner, [o], ou in NervesHub.Accounts.OrgUser,
            on: ou.org_id == o.id
          )
          |> where([_o, ou], ou.user_id == ^user_id)
          |> where([_o, ou], is_nil(ou.deleted_at))
          |> where([o], is_nil(o.deleted_at))
          |> NervesHub.Repo.all()
          |> Enum.map(fn ecto_org ->
            ash_fields = [:id, :name, :audit_log_days_to_keep, :deleted_at, :inserted_at, :updated_at]
            attrs = Map.take(ecto_org, ash_fields)
            struct!(NervesHub.Ash.Accounts.Org, attrs)
          end)

        {:ok, results}
      end
    end

    create :create do
      primary? true
      accept [:name]
    end

    create :create_with_user do
      accept [:name]
      argument :user_id, :integer, allow_nil?: false

      manual fn changeset, _context ->
        user_id = changeset.arguments.user_id
        name = Ash.Changeset.get_attribute(changeset, :name)
        ecto_user = NervesHub.Repo.get!(NervesHub.Accounts.User, user_id)

        case Accounts.create_org(ecto_user, %{"name" => name}) do
          {:ok, ecto_org} ->
            ash_fields = [:id, :name, :audit_log_days_to_keep, :deleted_at, :inserted_at, :updated_at]
            {:ok, struct!(NervesHub.Ash.Accounts.Org, Map.take(ecto_org, ash_fields))}

          {:error, error} ->
            {:error, error}
        end
      end
    end

    update :update do
      primary? true
      accept [:name, :audit_log_days_to_keep]

      manual fn changeset, _context ->
        ecto_org = NervesHub.Repo.get!(NervesHub.Accounts.Org, changeset.data.id)

        attrs =
          [:name, :audit_log_days_to_keep]
          |> Enum.reduce(%{}, fn field, acc ->
            case Ash.Changeset.get_attribute(changeset, field) do
              nil -> acc
              value -> Map.put(acc, to_string(field), value)
            end
          end)

        case Accounts.update_org(ecto_org, attrs) do
          {:ok, updated} ->
            ash_fields = [:id, :name, :audit_log_days_to_keep, :deleted_at, :inserted_at, :updated_at]
            {:ok, struct!(NervesHub.Ash.Accounts.Org, Map.take(updated, ash_fields))}

          {:error, error} ->
            {:error, error}
        end
      end
    end

    destroy :destroy do
      primary? true
      manual fn changeset, _context ->
        ecto_org = NervesHub.Repo.get!(NervesHub.Accounts.Org, changeset.data.id)

        case Accounts.soft_delete_org(ecto_org) do
          {:ok, _} -> {:ok, changeset.data}
          {:error, error} -> {:error, error}
        end
      end
    end
  end

  code_interface do
    define :read
    define :get, action: :read, get_by: [:id], not_found_error?: true
    define :get_by_name, args: [:name], get?: true
    define :get_for_user, args: [:user_id]
    define :create
    define :create_with_user, args: [:user_id]
    define :update
    define :destroy
  end
end

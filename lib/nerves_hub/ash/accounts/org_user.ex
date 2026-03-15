defmodule NervesHub.Ash.Accounts.OrgUser do
  use Ash.Resource,
    domain: NervesHub.Ash.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  alias NervesHub.Accounts

  postgres do
    table "org_users"
    repo NervesHub.Repo
  end

  json_api do
    type "org-user"
    derive_filter? false

    routes do
      base "/org-users"

      index :read
      index :list_by_org, route: "/by-org/:org_id"
      get :get_by_org_and_user, route: "/by-org/:org_id/user/:user_id"
      index :list_admins_by_org, route: "/admins-by-org/:org_id"
      post :create
      post :add_to_org, route: "/add-to-org"
      get :read, route: "/:id"
      patch :update
      delete :destroy
    end
  end

  graphql do
    encode_primary_key? false
    type :org_user

    queries do
      get :get_org_user, :read
      list :list_org_users, :read
      list :list_org_users_by_org, :list_by_org
      get :get_org_user_by_org_and_user, :get_by_org_and_user
      list :list_org_admins_by_org, :list_admins_by_org
      list :check_org_membership, :check_membership
    end

    mutations do
      create :create_org_user, :create
      create :add_user_to_org, :add_to_org
      update :update_org_user, :update
      update :change_org_user_role, :change_role
      destroy :destroy_org_user, :destroy
    end
  end

  attributes do
    integer_primary_key :id

    attribute :org_id, :integer, allow_nil?: false, public?: true
    attribute :user_id, :integer, allow_nil?: false, public?: true
    attribute :role, :atom, constraints: [one_of: [:admin, :manage, :view]], public?: true
    attribute :deleted_at, :utc_datetime, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :org, NervesHub.Ash.Accounts.Org do
      public? true
      source_attribute :org_id
      destination_attribute :id
    end

    belongs_to :user, NervesHub.Ash.Accounts.User do
      public? true
      source_attribute :user_id
      destination_attribute :id
    end
  end

  actions do
    defaults [:read]

    read :list_by_org do
      argument :org_id, :integer, allow_nil?: false

      filter expr(org_id == ^arg(:org_id) and is_nil(deleted_at))
    end

    read :get_by_org_and_user do
      argument :org_id, :integer, allow_nil?: false
      argument :user_id, :integer, allow_nil?: false

      filter expr(org_id == ^arg(:org_id) and user_id == ^arg(:user_id) and is_nil(deleted_at))
    end

    read :list_admins_by_org do
      argument :org_id, :integer, allow_nil?: false

      filter expr(org_id == ^arg(:org_id) and role == :admin and is_nil(deleted_at))
    end

    read :check_membership do
      argument :org_id, :integer, allow_nil?: false
      argument :user_id, :integer, allow_nil?: false

      filter expr(org_id == ^arg(:org_id) and user_id == ^arg(:user_id))
    end

    read :list_by_user do
      argument :user_id, :integer, allow_nil?: false

      filter expr(user_id == ^arg(:user_id) and is_nil(deleted_at))
    end

    action :has_role, :boolean do
      argument :org_id, :integer, allow_nil?: false
      argument :user_id, :integer, allow_nil?: false
      argument :role, :atom, allow_nil?: false, constraints: [one_of: [:admin, :manage, :view]]

      run fn input, _context ->
        ecto_org = %NervesHub.Accounts.Org{id: input.arguments.org_id}
        ecto_user = %NervesHub.Accounts.User{id: input.arguments.user_id}
        {:ok, Accounts.has_org_role?(ecto_org, ecto_user, input.arguments.role)}
      end
    end

    action :user_in_org, :boolean do
      argument :user_id, :integer, allow_nil?: false
      argument :org_id, :integer, allow_nil?: false

      run fn input, _context ->
        {:ok, Accounts.user_in_org?(input.arguments.user_id, input.arguments.org_id)}
      end
    end

    create :create do
      accept [:org_id, :user_id, :role]
    end

    create :add_to_org do
      accept [:role]
      argument :org_id, :integer, allow_nil?: false
      argument :user_id, :integer, allow_nil?: false

      manual fn changeset, _context ->
        org_id = changeset.arguments.org_id
        user_id = changeset.arguments.user_id
        role = Ash.Changeset.get_attribute(changeset, :role) || :view

        ecto_org = NervesHub.Repo.get!(NervesHub.Accounts.Org, org_id)
        ecto_user = NervesHub.Repo.get!(NervesHub.Accounts.User, user_id)

        case Accounts.add_org_user(ecto_org, ecto_user, %{role: role}) do
          {:ok, ecto_ou} ->
            ash_fields = [:id, :org_id, :user_id, :role, :deleted_at, :inserted_at, :updated_at]
            {:ok, struct!(NervesHub.Ash.Accounts.OrgUser, Map.take(ecto_ou, ash_fields))}

          {:error, error} ->
            {:error, error}
        end
      end
    end

    update :update do
      accept [:role]
    end

    update :change_role do
      accept []
      argument :role, :atom, allow_nil?: false, constraints: [one_of: [:admin, :manage, :view]]

      manual fn changeset, _context ->
        role = changeset.arguments.role
        ecto_ou = NervesHub.Repo.get!(NervesHub.Accounts.OrgUser, changeset.data.id)

        case Accounts.change_org_user_role(ecto_ou, role) do
          {:ok, updated} ->
            ash_fields = [:id, :org_id, :user_id, :role, :deleted_at, :inserted_at, :updated_at]
            {:ok, struct!(NervesHub.Ash.Accounts.OrgUser, Map.take(updated, ash_fields))}

          {:error, error} ->
            {:error, error}
        end
      end
    end

    destroy :destroy do
      manual fn changeset, _context ->
        ecto_org_user = NervesHub.Repo.get!(NervesHub.Accounts.OrgUser, changeset.data.id)

        case Accounts.soft_delete_org_user(ecto_org_user) do
          :ok -> {:ok, changeset.data}
          {:error, error} -> {:error, error}
        end
      end
    end

    destroy :remove_from_org do
      argument :org_id, :integer, allow_nil?: false
      argument :user_id, :integer, allow_nil?: false

      manual fn changeset, _context ->
        org_id = changeset.arguments.org_id
        user_id = changeset.arguments.user_id

        ecto_org = NervesHub.Repo.get!(NervesHub.Accounts.Org, org_id)
        ecto_user = NervesHub.Repo.get!(NervesHub.Accounts.User, user_id)

        case Accounts.remove_org_user(ecto_org, ecto_user) do
          :ok -> {:ok, changeset.data}
          {:error, error} -> {:error, error}
        end
      end
    end
  end

  code_interface do
    define :read
    define :list_by_org, args: [:org_id]
    define :get_by_org_and_user, args: [:org_id, :user_id], get?: true
    define :list_admins_by_org, args: [:org_id]
    define :check_membership, args: [:org_id, :user_id]
    define :list_by_user, args: [:user_id]
    define :has_role, args: [:org_id, :user_id, :role]
    define :user_in_org, args: [:user_id, :org_id]
    define :add_to_org
    define :change_role, args: [:role]
    define :remove_from_org, args: [:org_id, :user_id]
  end
end

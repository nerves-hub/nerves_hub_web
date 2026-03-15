defmodule NervesHub.Ash.Accounts.User do
  use Ash.Resource,
    domain: NervesHub.Ash.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  alias NervesHub.Accounts

  postgres do
    table "users"
    repo NervesHub.Repo
  end

  json_api do
    type "user"
    derive_filter? false

    routes do
      base "/users"

      index :read
      get :read, route: "/:id"
      get :get_by_email, route: "/by-email/:email"
      post :create
      patch :update
    end
  end

  graphql do
    encode_primary_key? false
    type :user

    queries do
      get :get_user, :read
      list :list_users, :read
      get :get_user_by_email, :get_by_email
    end

    mutations do
      create :create_user, :create
      update :update_user, :update
    end
  end

  attributes do
    integer_primary_key :id

    attribute :name, :string, public?: true, source: :username
    attribute :email, :string, allow_nil?: false, public?: true
    attribute :password_hash, :string, public?: false
    attribute :profile_picture_url, :string, public?: true
    attribute :google_id, :string, public?: true
    attribute :google_hd, :string, public?: true
    attribute :google_last_synced_at, :naive_datetime, public?: true
    attribute :confirmed_at, :naive_datetime, public?: true
    attribute :deleted_at, :utc_datetime, public?: true
    attribute :server_role, :atom, constraints: [one_of: [:admin, :view]], public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :org_users, NervesHub.Ash.Accounts.OrgUser do
      public? true
      source_attribute :id
      destination_attribute :user_id
    end

    has_many :user_tokens, NervesHub.Ash.Accounts.UserToken do
      public? true
      source_attribute :id
      destination_attribute :user_id
    end
  end

  actions do
    defaults [:read]

    read :get_by_email do
      argument :email, :string, allow_nil?: false

      filter expr(email == ^arg(:email) and is_nil(deleted_at))
    end

    create :create do
      primary? true
      accept [:name, :email]
      argument :password, :string

      manual fn changeset, _context ->
        params = %{
          "name" => Ash.Changeset.get_attribute(changeset, :name),
          "email" => Ash.Changeset.get_attribute(changeset, :email),
          "password" => changeset.arguments[:password] || "default_password"
        }

        case Accounts.create_user(params) do
          {:ok, ecto_user} ->
            {:ok, ecto_to_ash(ecto_user)}

          {:error, error} ->
            {:error, error}
        end
      end
    end

    update :confirm do
      accept []

      manual fn changeset, _context ->
        ecto_user = NervesHub.Repo.get!(NervesHub.Accounts.User, changeset.data.id)

        case Accounts.confirm_user(ecto_user) do
          {:ok, updated} -> {:ok, ecto_to_ash(updated)}
          {:error, error} -> {:error, error}
        end
      end
    end

    update :update do
      primary? true
      accept [:name, :email]

      manual fn changeset, _context ->
        ecto_user = NervesHub.Repo.get!(NervesHub.Accounts.User, changeset.data.id)

        params =
          [:name, :email]
          |> Enum.reduce(%{}, fn field, acc ->
            case Ash.Changeset.get_attribute(changeset, field) do
              nil -> acc
              value -> Map.put(acc, to_string(field), value)
            end
          end)

        case Accounts.update_user(ecto_user, params) do
          {:ok, updated} -> {:ok, ecto_to_ash(updated)}
          {:error, error} -> {:error, error}
        end
      end
    end
  end

  code_interface do
    define :read
    define :get, action: :read, get_by: [:id], not_found_error?: true
    define :get_by_email, args: [:email], get?: true
    define :create
    define :update
    define :confirm
  end

  defp ecto_to_ash(ecto_user) do
    attrs = %{
      id: ecto_user.id,
      name: ecto_user.name,
      email: ecto_user.email,
      confirmed_at: ecto_user.confirmed_at,
      deleted_at: ecto_user.deleted_at,
      inserted_at: ecto_user.inserted_at,
      updated_at: ecto_user.updated_at
    }

    struct!(__MODULE__, attrs)
  end
end

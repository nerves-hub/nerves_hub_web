defmodule NervesHub.Ash.Accounts.UserToken do
  use Ash.Resource,
    domain: NervesHub.Ash.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  alias NervesHub.Accounts

  postgres do
    table "user_tokens"
    repo NervesHub.Repo
  end

  json_api do
    type "user-token"
    derive_filter? false

    routes do
      base "/user-tokens"

      index :read
      index :list_by_user, route: "/by-user/:user_id"
      get :read, route: "/:id"
      post :create_api_token
      delete :destroy
    end
  end

  graphql do
    encode_primary_key? false
    type :user_token

    queries do
      get :get_user_token, :read
      list :list_user_tokens, :read
      list :list_user_tokens_by_user, :list_by_user
    end

    mutations do
      create :create_user_api_token, :create_api_token
      destroy :destroy_user_token, :destroy
    end
  end

  attributes do
    integer_primary_key :id

    attribute :user_id, :integer, allow_nil?: false, public?: true
    attribute :token, :binary, public?: false
    attribute :context, :string, public?: true
    attribute :note, :string, public?: true
    attribute :last_used, :utc_datetime, public?: true
    attribute :old_token, :string, public?: false

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, NervesHub.Ash.Accounts.User do
      public? true
      source_attribute :user_id
      destination_attribute :id
    end
  end

  actions do
    defaults [:read]

    read :list_by_user do
      argument :user_id, :integer, allow_nil?: false

      filter expr(user_id == ^arg(:user_id) and context == "api")
    end

    create :create_api_token do
      accept []
      argument :user_id, :integer, allow_nil?: false
      argument :note, :string, allow_nil?: false

      manual fn changeset, _context ->
        user_id = changeset.arguments.user_id
        note = changeset.arguments.note
        user = NervesHub.Repo.get!(NervesHub.Accounts.User, user_id)

        encoded_token = Accounts.create_user_api_token(user, note)

        # Fetch the just-created token to return it
        case Accounts.get_user_token(encoded_token) do
          {:ok, ecto_token} -> {:ok, ecto_to_ash(ecto_token)}
          {:error, _} -> {:error, "Failed to create token"}
        end
      end
    end

    update :mark_last_used do
      accept []

      manual fn changeset, _context ->
        ecto_token = NervesHub.Repo.get!(NervesHub.Accounts.UserToken, changeset.data.id)

        case Accounts.mark_last_used(ecto_token) do
          :ok ->
            updated = NervesHub.Repo.get!(NervesHub.Accounts.UserToken, changeset.data.id)
            {:ok, ecto_to_ash(updated)}

          :error ->
            {:error, "Failed to mark token as used"}
        end
      end
    end

    destroy :destroy do
      primary? true
      manual fn changeset, _context ->
        ecto_token = NervesHub.Repo.get!(NervesHub.Accounts.UserToken, changeset.data.id)

        case NervesHub.Repo.delete(ecto_token) do
          {:ok, _} -> {:ok, changeset.data}
          {:error, error} -> {:error, error}
        end
      end
    end
  end

  code_interface do
    define :read
    define :get, action: :read, get_by: [:id], not_found_error?: true
    define :list_by_user, args: [:user_id]
    define :create_api_token, args: [:user_id, :note]
    define :mark_last_used
    define :destroy
  end

  defp ecto_to_ash(ecto_token) do
    ash_fields = [
      :id, :user_id, :token, :context, :note, :last_used,
      :old_token, :inserted_at, :updated_at
    ]

    struct!(__MODULE__, Map.take(ecto_token, ash_fields))
  end
end

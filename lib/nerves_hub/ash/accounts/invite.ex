defmodule NervesHub.Ash.Accounts.Invite do
  use Ash.Resource,
    domain: NervesHub.Ash.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  alias NervesHub.Accounts

  postgres do
    table "invites"
    repo NervesHub.Repo
  end

  json_api do
    type "invite"
    derive_filter? false

    routes do
      base "/invites"

      index :read
      get :read, route: "/:id"
      get :get_valid, route: "/by-token/:token"
      index :list_for_org, route: "/for-org/:org_id"
      post :create
      delete :destroy
    end
  end

  graphql do
    encode_primary_key? false
    type :invite

    queries do
      get :get_invite, :read
      list :list_invites, :read
      get :get_valid_invite, :get_valid
      list :list_invites_for_org, :list_for_org
    end

    mutations do
      create :create_invite, :create
      update :accept_invite, :accept
      destroy :destroy_invite, :destroy
    end
  end

  attributes do
    integer_primary_key :id

    attribute :org_id, :integer, allow_nil?: false, public?: true
    attribute :invited_by_id, :integer, public?: true
    attribute :email, :string, allow_nil?: false, public?: true
    attribute :token, :uuid, allow_nil?: false, public?: true
    attribute :accepted, :boolean, default: false, public?: true
    attribute :role, :atom, constraints: [one_of: [:admin, :manage, :view]], public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :org, NervesHub.Ash.Accounts.Org do
      public? true
      source_attribute :org_id
      destination_attribute :id
    end

    belongs_to :invited_by, NervesHub.Ash.Accounts.User do
      public? true
      source_attribute :invited_by_id
      destination_attribute :id
    end
  end

  actions do
    defaults [:read]

    read :get_valid do
      argument :token, :uuid, allow_nil?: false

      manual fn ash_query, _ecto_query, _context ->
        token = ash_query.arguments.token

        case Accounts.get_valid_invite(token) do
          {:ok, ecto_invite} ->
            {:ok, [ecto_to_ash(ecto_invite)]}

          {:error, :invite_not_found} ->
            {:ok, []}
        end
      end
    end

    read :list_for_org do
      argument :org_id, :integer, allow_nil?: false

      manual fn ash_query, _ecto_query, _context ->
        org_id = ash_query.arguments.org_id
        ecto_org = NervesHub.Repo.get!(NervesHub.Accounts.Org, org_id)

        results =
          Accounts.get_invites_for_org(ecto_org)
          |> Enum.map(&ecto_to_ash/1)

        {:ok, results}
      end
    end

    create :create do
      accept [:email, :org_id, :invited_by_id, :role]

      change fn changeset, _context ->
        Ash.Changeset.force_change_attribute(changeset, :token, Ecto.UUID.generate())
      end
    end

    update :accept do
      accept []

      manual fn changeset, _context ->
        ecto_invite = NervesHub.Repo.get!(NervesHub.Accounts.Invite, changeset.data.id)

        case NervesHub.Repo.update(Ecto.Changeset.change(ecto_invite, accepted: true)) do
          {:ok, updated} -> {:ok, ecto_to_ash(updated)}
          {:error, error} -> {:error, error}
        end
      end
    end

    destroy :destroy do
      manual fn changeset, _context ->
        ecto_org = NervesHub.Repo.get!(NervesHub.Accounts.Org, changeset.data.org_id)

        case Accounts.delete_invite(ecto_org, changeset.data.token) do
          {:ok, _} -> {:ok, changeset.data}
          {:error, error} -> {:error, error}
        end
      end
    end
  end

  code_interface do
    define :read
    define :get, action: :read, get_by: [:id], not_found_error?: true
    define :get_valid, args: [:token], get?: true
    define :list_for_org, args: [:org_id]
    define :create
    define :accept
    define :destroy
  end

  defp ecto_to_ash(ecto_invite) do
    ash_fields = [:id, :org_id, :invited_by_id, :email, :token, :accepted, :role, :inserted_at, :updated_at]
    attrs = Map.take(ecto_invite, ash_fields)
    struct!(__MODULE__, attrs)
  end
end

defmodule NervesHub.Ash.Devices.CACertificate do
  use Ash.Resource,
    domain: NervesHub.Ash.Devices,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  alias NervesHub.Devices

  postgres do
    table "ca_certificates"
    repo NervesHub.Repo
  end

  json_api do
    type "ca-certificate"
    derive_filter? false

    routes do
      base "/ca-certificates"

      index :read
      index :list_by_org, route: "/by-org/:org_id"
      get :read, route: "/:id"
      get :get_by_org_and_serial, route: "/by-org/:org_id/serial/:serial"
      delete :destroy
    end
  end

  graphql do
    encode_primary_key? false
    type :ca_certificate

    queries do
      get :get_ca_certificate, :read
      list :list_ca_certificates, :read
      list :list_ca_certificates_by_org, :list_by_org
      get :get_ca_certificate_by_org_and_serial, :get_by_org_and_serial
    end

    mutations do
      destroy :destroy_ca_certificate, :destroy
    end
  end

  attributes do
    integer_primary_key :id

    attribute :org_id, :integer, allow_nil?: false, public?: true
    attribute :jitp_id, :integer, public?: true
    attribute :serial, :string, allow_nil?: false, public?: true
    attribute :description, :string, public?: true
    attribute :aki, :binary, public?: false
    attribute :ski, :binary, public?: false
    attribute :not_before, :utc_datetime, public?: true
    attribute :not_after, :utc_datetime, public?: true
    attribute :last_used, :utc_datetime, public?: true
    attribute :der, :binary, public?: false
    attribute :check_expiration, :boolean, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :org, NervesHub.Ash.Accounts.Org do
      public? true
      source_attribute :org_id
      destination_attribute :id
    end

    belongs_to :jitp, NervesHub.Ash.Devices.JITP do
      public? true
      source_attribute :jitp_id
      destination_attribute :id
    end
  end

  actions do
    defaults [:read]

    read :list_by_org do
      argument :org_id, :integer, allow_nil?: false

      filter expr(org_id == ^arg(:org_id))
    end

    read :get_by_org_and_serial do
      argument :org_id, :integer, allow_nil?: false
      argument :serial, :string, allow_nil?: false

      filter expr(org_id == ^arg(:org_id) and serial == ^arg(:serial))
    end

    read :get_by_serial do
      argument :serial, :string, allow_nil?: false

      filter expr(serial == ^arg(:serial))
    end

    read :get_by_aki do
      argument :aki, :binary, allow_nil?: false

      filter expr(aki == ^arg(:aki))
    end

    read :get_by_ski do
      argument :ski, :binary, allow_nil?: false

      filter expr(ski == ^arg(:ski))
    end

    action :known_ski, :boolean do
      argument :ski, :binary, allow_nil?: false

      run fn input, _context ->
        {:ok, Devices.known_ca_ski?(input.arguments.ski)}
      end
    end

    create :create do
      accept [:org_id, :serial, :description, :aki, :ski, :not_before, :not_after, :der, :check_expiration, :jitp_id]
    end

    update :update do
      primary? true
      accept [:description, :check_expiration, :last_used]
    end

    destroy :destroy do
      primary? true
      manual fn changeset, _context ->
        ecto_cert = NervesHub.Repo.get!(NervesHub.Devices.CACertificate, changeset.data.id)

        case Devices.delete_ca_certificate(ecto_cert) do
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
    define :get_by_org_and_serial, args: [:org_id, :serial], get?: true
    define :get_by_serial, args: [:serial], get?: true
    define :get_by_aki, args: [:aki], get?: true
    define :get_by_ski, args: [:ski], get?: true
    define :known_ski, args: [:ski]
    define :create
    define :update
    define :destroy
  end
end

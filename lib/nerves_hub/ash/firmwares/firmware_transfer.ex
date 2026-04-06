defmodule NervesHub.Ash.Firmwares.FirmwareTransfer do
  use Ash.Resource,
    domain: NervesHub.Ash.Firmwares,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  postgres do
    table "firmware_transfers"
    repo NervesHub.Repo
  end

  json_api do
    type "firmware-transfer"
    derive_filter? false

    routes do
      base "/firmware-transfers"

      index :read
      index :list_by_org, route: "/by-org/:org_id"
      get :read, route: "/:id"
    end
  end

  graphql do
    encode_primary_key? false
    type :firmware_transfer

    queries do
      get :get_firmware_transfer, :read
      list :list_firmware_transfers, :read
      list :list_firmware_transfers_by_org, :list_by_org
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :org_id, :integer, allow_nil?: false, public?: true
    attribute :firmware_uuid, :string, public?: true
    attribute :remote_ip, :string, public?: true
    attribute :bytes_total, :integer, public?: true
    attribute :bytes_sent, :integer, public?: true
    attribute :timestamp, :utc_datetime, public?: true
  end

  relationships do
    belongs_to :org, NervesHub.Ash.Accounts.Org do
      public? true
      source_attribute :org_id
      destination_attribute :id
    end
  end

  actions do
    defaults [:read]

    read :list_by_org do
      argument :org_id, :integer, allow_nil?: false

      filter expr(org_id == ^arg(:org_id))
    end

    create :create do
      accept [:org_id, :firmware_uuid, :remote_ip, :bytes_total, :bytes_sent, :timestamp]
    end
  end

  code_interface do
    define :read
    define :get, action: :read, get_by: [:id], not_found_error?: true
    define :list_by_org, args: [:org_id]
    define :create
  end
end

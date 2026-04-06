defmodule NervesHub.Ash.Devices.DeviceConnection do
  use Ash.Resource,
    domain: NervesHub.Ash.Devices,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  postgres do
    table "device_connections"
    repo NervesHub.Repo
  end

  json_api do
    type "device-connection"
    derive_filter? false

    routes do
      base "/device-connections"

      index :read
      index :list_by_device, route: "/by-device/:device_id"
      get :read, route: "/:id"
    end
  end

  graphql do
    encode_primary_key? false
    type :device_connection_record

    queries do
      get :get_device_connection, :read
      list :list_device_connections, :read
      list :list_device_connections_by_device, :list_by_device
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :product_id, :integer, allow_nil?: false, public?: true
    attribute :device_id, :integer, allow_nil?: false, public?: true
    attribute :established_at, :utc_datetime_usec, public?: true
    attribute :last_seen_at, :utc_datetime_usec, public?: true
    attribute :disconnected_at, :utc_datetime_usec, public?: true
    attribute :disconnected_reason, :string, public?: true
    attribute :metadata, :map, default: %{}, public?: true
    attribute :status, :atom, constraints: [one_of: [:connecting, :connected, :disconnected]], default: :connecting, public?: true
  end

  relationships do
    belongs_to :product, NervesHub.Ash.Products.Product do
      public? true
      source_attribute :product_id
      destination_attribute :id
    end

    belongs_to :device, NervesHub.Ash.Devices.Device do
      public? true
      source_attribute :device_id
      destination_attribute :id
    end
  end

  actions do
    defaults [:read]

    read :list_by_device do
      argument :device_id, :integer, allow_nil?: false

      filter expr(device_id == ^arg(:device_id))
    end

    read :get_latest_for_device do
      argument :device_id, :integer, allow_nil?: false

      filter expr(device_id == ^arg(:device_id))

      prepare fn query, _context ->
        Ash.Query.sort(query, established_at: :desc)
        |> Ash.Query.limit(1)
      end
    end
  end

  code_interface do
    define :read
    define :get, action: :read, get_by: [:id], not_found_error?: true
    define :list_by_device, args: [:device_id]
    define :get_latest_for_device, args: [:device_id], get?: true
  end
end

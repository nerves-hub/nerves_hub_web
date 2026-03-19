defmodule NervesHub.Ash.Devices.DeviceHealth do
  use Ash.Resource,
    domain: NervesHub.Ash.Devices,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  postgres do
    table "device_health"
    repo NervesHub.Repo
  end

  json_api do
    type "device-health"
    derive_filter? false

    routes do
      base "/device-health"

      index :read
      index :list_by_device, route: "/by-device/:device_id"
      get :read, route: "/:id"
    end
  end

  graphql do
    encode_primary_key? false
    type :device_health

    queries do
      get :get_device_health, :read
      list :list_device_health, :read
      list :list_device_health_by_device, :list_by_device
    end
  end

  attributes do
    integer_primary_key :id

    attribute :device_id, :integer, allow_nil?: false, public?: true
    attribute :data, :map, public?: true
    attribute :status, :atom, constraints: [one_of: [:unknown, :healthy, :warning, :unhealthy]], default: :unknown, public?: true
    attribute :status_reasons, :map, public?: true

    create_timestamp :inserted_at, type: :utc_datetime_usec
  end

  relationships do
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

    read :get_latest do
      argument :device_id, :integer, allow_nil?: false

      filter expr(device_id == ^arg(:device_id))

      prepare fn query, _context ->
        Ash.Query.sort(query, inserted_at: :desc)
        |> Ash.Query.limit(1)
      end
    end

    create :create do
      accept [:device_id, :data, :status, :status_reasons]
    end
  end

  code_interface do
    define :read
    define :get, action: :read, get_by: [:id], not_found_error?: true
    define :list_by_device, args: [:device_id]
    define :get_latest, args: [:device_id], get?: true
    define :create
  end
end

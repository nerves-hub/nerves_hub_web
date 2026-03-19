defmodule NervesHub.Ash.Devices.DeviceMetric do
  use Ash.Resource,
    domain: NervesHub.Ash.Devices,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  postgres do
    table "device_metrics"
    repo NervesHub.Repo
  end

  json_api do
    type "device-metric"
    derive_filter? false

    routes do
      base "/device-metrics"

      index :read
      index :list_by_device, route: "/by-device/:device_id"
      get :read, route: "/:id"
    end
  end

  graphql do
    encode_primary_key? false
    type :device_metric

    queries do
      get :get_device_metric, :read
      list :list_device_metrics, :read
      list :list_device_metrics_by_device, :list_by_device
    end
  end

  attributes do
    integer_primary_key :id

    attribute :device_id, :integer, allow_nil?: false, public?: true
    attribute :key, :string, allow_nil?: false, public?: true
    attribute :value, :float, allow_nil?: false, public?: true

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

    read :list_by_device_and_key do
      argument :device_id, :integer, allow_nil?: false
      argument :key, :string, allow_nil?: false

      filter expr(device_id == ^arg(:device_id) and key == ^arg(:key))
    end

    create :create do
      accept [:device_id, :key, :value]
    end
  end

  code_interface do
    define :read
    define :get, action: :read, get_by: [:id], not_found_error?: true
    define :list_by_device, args: [:device_id]
    define :list_by_device_and_key, args: [:device_id, :key]
    define :create
  end
end

defmodule NervesHub.Ash.Devices.DeviceSharedSecretAuth do
  use Ash.Resource,
    domain: NervesHub.Ash.Devices,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  postgres do
    table "device_shared_secret_auths"
    repo NervesHub.Repo
  end

  json_api do
    type "device-shared-secret-auth"
    derive_filter? false

    routes do
      base "/device-shared-secret-auths"

      index :read
      index :list_by_device, route: "/by-device/:device_id"
      get :read, route: "/:id"
    end
  end

  graphql do
    encode_primary_key? false
    type :device_shared_secret_auth

    queries do
      get :get_device_shared_secret_auth, :read
      list :list_device_shared_secret_auths, :read
      list :list_device_shared_secret_auths_by_device, :list_by_device
    end
  end

  attributes do
    integer_primary_key :id

    attribute :device_id, :integer, allow_nil?: false, public?: true
    attribute :product_shared_secret_auth_id, :integer, public?: true
    # key and secret are sensitive - not exposed via API
    attribute :key, :string, public?: false
    attribute :secret, :string, public?: false
    attribute :deactivated_at, :utc_datetime, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :device, NervesHub.Ash.Devices.Device do
      public? true
      source_attribute :device_id
      destination_attribute :id
    end

    belongs_to :product_shared_secret_auth, NervesHub.Ash.Products.SharedSecretAuth do
      public? true
      source_attribute :product_shared_secret_auth_id
      destination_attribute :id
    end
  end

  actions do
    defaults [:read]

    read :list_by_device do
      argument :device_id, :integer, allow_nil?: false

      filter expr(device_id == ^arg(:device_id))
    end

    read :get_active_by_key do
      argument :key, :string, allow_nil?: false

      filter expr(key == ^arg(:key) and is_nil(deactivated_at))
    end

    create :create do
      argument :device_id, :integer, allow_nil?: false

      manual fn changeset, _context ->
        device_id = changeset.arguments.device_id
        ecto_device = NervesHub.Repo.get!(NervesHub.Devices.Device, device_id)

        case NervesHub.Devices.create_shared_secret_auth(ecto_device) do
          {:ok, ecto_auth} ->
            ash_fields = [:id, :device_id, :product_shared_secret_auth_id, :key, :secret, :deactivated_at, :inserted_at, :updated_at]
            {:ok, struct!(NervesHub.Ash.Devices.DeviceSharedSecretAuth, Map.take(ecto_auth, ash_fields))}

          {:error, error} ->
            {:error, error}
        end
      end
    end

    destroy :destroy do
      primary? true
    end
  end

  code_interface do
    define :read
    define :get, action: :read, get_by: [:id], not_found_error?: true
    define :list_by_device, args: [:device_id]
    define :get_active_by_key, args: [:key], get?: true
    define :create
    define :destroy
  end
end

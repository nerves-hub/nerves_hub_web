defmodule NervesHub.Ash.Devices.PinnedDevice do
  use Ash.Resource,
    domain: NervesHub.Ash.Devices,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  postgres do
    table "pinned_devices"
    repo NervesHub.Repo
  end

  json_api do
    type "pinned-device"
    derive_filter? false

    routes do
      base "/pinned-devices"

      index :read
      index :list_by_user, route: "/by-user/:user_id"
      get :read, route: "/:id"
      post :create
      delete :destroy
    end
  end

  graphql do
    encode_primary_key? false
    type :pinned_device

    queries do
      get :get_pinned_device, :read
      list :list_pinned_devices, :read
      list :list_pinned_devices_by_user, :list_by_user
    end

    mutations do
      create :create_pinned_device, :create
      destroy :destroy_pinned_device, :destroy
    end
  end

  attributes do
    integer_primary_key :id

    attribute :user_id, :integer, allow_nil?: false, public?: true
    attribute :device_id, :integer, allow_nil?: false, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :user, NervesHub.Ash.Accounts.User do
      public? true
      source_attribute :user_id
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

    read :list_by_user do
      argument :user_id, :integer, allow_nil?: false

      filter expr(user_id == ^arg(:user_id))
    end

    create :create do
      accept [:user_id, :device_id]
    end

    destroy :destroy do
      primary? true
    end
  end

  code_interface do
    define :read
    define :get, action: :read, get_by: [:id], not_found_error?: true
    define :list_by_user, args: [:user_id]
    define :create
    define :destroy
  end
end

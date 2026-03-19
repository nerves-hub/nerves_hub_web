defmodule NervesHub.Ash.Devices.DeviceCertificate do
  use Ash.Resource,
    domain: NervesHub.Ash.Devices,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  alias NervesHub.Devices

  postgres do
    table "device_certificates"
    repo NervesHub.Repo
  end

  json_api do
    type "device-certificate"
    derive_filter? false

    routes do
      base "/device-certificates"

      index :read
      index :list_by_device, route: "/by-device/:device_id"
      get :read, route: "/:id"
      get :get_by_device_and_serial, route: "/by-device/:device_id/serial/:serial"
      delete :destroy
    end
  end

  graphql do
    encode_primary_key? false
    type :device_certificate

    queries do
      get :get_device_certificate, :read
      list :list_device_certificates, :read
      list :list_device_certificates_by_device, :list_by_device
      get :get_device_certificate_by_serial, :get_by_device_and_serial
    end

    mutations do
      destroy :destroy_device_certificate, :destroy
    end
  end

  attributes do
    integer_primary_key :id

    attribute :device_id, :integer, allow_nil?: false, public?: true
    attribute :org_id, :integer, public?: true
    attribute :serial, :string, allow_nil?: false, public?: true
    attribute :aki, :binary, public?: false
    attribute :ski, :binary, public?: false
    attribute :not_before, :utc_datetime, public?: true
    attribute :not_after, :utc_datetime, public?: true
    attribute :last_used, :utc_datetime, public?: true
    attribute :der, :binary, public?: false
    attribute :fingerprint, :string, public?: true
    attribute :public_key_fingerprint, :string, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
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

    read :get_by_device_and_serial do
      argument :device_id, :integer, allow_nil?: false
      argument :serial, :string, allow_nil?: false

      filter expr(device_id == ^arg(:device_id) and serial == ^arg(:serial))
    end

    read :get_by_fingerprint do
      argument :fingerprint, :string, allow_nil?: false

      filter expr(fingerprint == ^arg(:fingerprint))
    end

    read :get_by_public_key_fingerprint do
      argument :public_key_fingerprint, :string, allow_nil?: false

      filter expr(public_key_fingerprint == ^arg(:public_key_fingerprint))
    end

    create :create do
      accept [:device_id, :org_id, :serial, :aki, :ski, :not_before, :not_after, :der, :fingerprint, :public_key_fingerprint]
    end

    update :update do
      primary? true
      accept [:last_used]
    end

    destroy :destroy do
      primary? true
      manual fn changeset, _context ->
        ecto_cert = NervesHub.Repo.get!(NervesHub.Devices.DeviceCertificate, changeset.data.id)

        case Devices.delete_device_certificate(ecto_cert) do
          {:ok, _} -> {:ok, changeset.data}
          {:error, error} -> {:error, error}
        end
      end
    end
  end

  code_interface do
    define :read
    define :get, action: :read, get_by: [:id], not_found_error?: true
    define :list_by_device, args: [:device_id]
    define :get_by_device_and_serial, args: [:device_id, :serial], get?: true
    define :get_by_fingerprint, args: [:fingerprint], get?: true
    define :get_by_public_key_fingerprint, args: [:public_key_fingerprint], get?: true
    define :create
    define :update
    define :destroy
  end
end

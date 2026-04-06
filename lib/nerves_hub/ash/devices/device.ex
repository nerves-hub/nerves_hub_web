defmodule NervesHub.Ash.Devices.Device do
  use Ash.Resource,
    domain: NervesHub.Ash.Devices,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  alias NervesHub.Devices

  postgres do
    table "devices"
    repo NervesHub.Repo
  end

  json_api do
    type "device"
    derive_filter? false

    includes [
      product: [],
      deployment_group: [],
      device_certificates: [],
      device_connections: [],
      device_health: [],
      device_metrics: [],
      inflight_updates: [],
      latest_connection: [],
      latest_health: []
    ]

    routes do
      base "/devices"

      index :read
      index :list_by_product, route: "/by-product/:org_id/:product_id"
      get :read, route: "/:id"
      get :get_by_identifier, route: "/by-identifier/:identifier"
      post :create
      patch :update
      delete :destroy
    end
  end

  graphql do
    encode_primary_key? false
    type :device

    queries do
      get :get_device, :read
      list :list_devices, :read
      list :list_devices_by_product, :list_by_product
      get :get_device_by_identifier, :get_by_identifier
    end

    mutations do
      create :create_device, :create
      update :update_device, :update
      destroy :destroy_device, :destroy
    end
  end

  attributes do
    integer_primary_key :id

    attribute :org_id, :integer, allow_nil?: false, public?: true
    attribute :product_id, :integer, allow_nil?: false, public?: true
    attribute :deployment_id, :integer, public?: true
    attribute :latest_connection_id, :uuid, public?: true
    attribute :latest_health_id, :integer, public?: true
    attribute :identifier, :string, allow_nil?: false, public?: true
    attribute :description, :string, public?: true
    attribute :tags, {:array, :string}, public?: true
    attribute :connecting_code, :string, public?: true
    attribute :custom_location_coordinates, {:array, :float}, public?: true
    attribute :firmware_metadata, :map, public?: true
    attribute :extensions, :map, public?: true
    attribute :status, :atom, constraints: [one_of: [:registered, :provisioned]], default: :registered, public?: true
    attribute :firmware_validation_status, :atom, constraints: [one_of: [:validated, :not_validated, :unknown]], default: :unknown, public?: true
    attribute :firmware_auto_revert_detected, :boolean, default: false, public?: true
    attribute :updates_enabled, :boolean, default: true, public?: true
    attribute :update_attempts, {:array, :utc_datetime}, default: [], public?: true
    attribute :updates_blocked_until, :utc_datetime, public?: true
    attribute :network_interface, :atom, constraints: [one_of: [:wifi, :ethernet, :cellular, :unknown]], public?: true
    attribute :first_seen_at, :utc_datetime, public?: true
    attribute :deleted_at, :utc_datetime, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :org, NervesHub.Ash.Accounts.Org do
      public? true
      source_attribute :org_id
      destination_attribute :id
    end

    belongs_to :product, NervesHub.Ash.Products.Product do
      public? true
      source_attribute :product_id
      destination_attribute :id
    end

    belongs_to :deployment_group, NervesHub.Ash.Deployments.DeploymentGroup do
      public? true
      source_attribute :deployment_id
      destination_attribute :id
    end

    belongs_to :latest_connection, NervesHub.Ash.Devices.DeviceConnection do
      public? true
      source_attribute :latest_connection_id
      destination_attribute :id
    end

    belongs_to :latest_health, NervesHub.Ash.Devices.DeviceHealth do
      public? true
      source_attribute :latest_health_id
      destination_attribute :id
    end

    has_many :device_certificates, NervesHub.Ash.Devices.DeviceCertificate do
      public? true
      source_attribute :id
      destination_attribute :device_id
    end

    has_many :device_connections, NervesHub.Ash.Devices.DeviceConnection do
      public? true
      source_attribute :id
      destination_attribute :device_id
    end

    has_many :device_health, NervesHub.Ash.Devices.DeviceHealth do
      public? true
      source_attribute :id
      destination_attribute :device_id
    end

    has_many :device_metrics, NervesHub.Ash.Devices.DeviceMetric do
      public? true
      source_attribute :id
      destination_attribute :device_id
    end

    has_many :inflight_updates, NervesHub.Ash.Devices.InflightUpdate do
      public? true
      source_attribute :id
      destination_attribute :device_id
    end
  end

  actions do
    defaults [:read]

    read :list_by_product do
      argument :org_id, :integer, allow_nil?: false
      argument :product_id, :integer, allow_nil?: false

      filter expr(org_id == ^arg(:org_id) and product_id == ^arg(:product_id) and is_nil(deleted_at))
    end

    read :get_by_identifier do
      argument :identifier, :string, allow_nil?: false

      filter expr(identifier == ^arg(:identifier) and is_nil(deleted_at))
    end

    read :get_by_org do
      argument :org_id, :integer, allow_nil?: false
      argument :device_id, :integer, allow_nil?: false

      filter expr(org_id == ^arg(:org_id) and id == ^arg(:device_id) and is_nil(deleted_at))
    end

    read :list_by_org do
      argument :org_id, :integer, allow_nil?: false

      filter expr(org_id == ^arg(:org_id) and is_nil(deleted_at))
    end

    action :count_by_org, :integer do
      argument :org_id, :integer, allow_nil?: false

      run fn input, _context ->
        {:ok, Devices.get_device_count_by_org_id(input.arguments.org_id)}
      end
    end

    action :count_by_product, :integer do
      argument :product_id, :integer, allow_nil?: false

      run fn input, _context ->
        {:ok, Devices.get_device_count_by_product_id(input.arguments.product_id)}
      end
    end

    action :count_by_org_and_product, :integer do
      argument :org_id, :integer, allow_nil?: false
      argument :product_id, :integer, allow_nil?: false

      run fn input, _context ->
        {:ok, Devices.get_device_count_by_org_id_and_product_id(
          input.arguments.org_id,
          input.arguments.product_id
        )}
      end
    end

    action :soft_deleted_exist_for_product, :boolean do
      argument :product_id, :integer, allow_nil?: false

      run fn input, _context ->
        {:ok, Devices.soft_deleted_devices_exist_for_product?(input.arguments.product_id)}
      end
    end

    action :in_penalty_box, :boolean do
      argument :device_id, :integer, allow_nil?: false

      run fn input, _context ->
        ecto_device = NervesHub.Repo.get!(NervesHub.Devices.Device, input.arguments.device_id)
        {:ok, Devices.device_in_penalty_box?(ecto_device)}
      end
    end

    action :has_certificates, :boolean do
      argument :device_id, :integer, allow_nil?: false

      run fn input, _context ->
        ecto_device = NervesHub.Repo.get!(NervesHub.Devices.Device, input.arguments.device_id)
        {:ok, Devices.has_device_certificates?(ecto_device)}
      end
    end

    create :create do
      primary? true
      accept [:identifier, :description, :org_id, :product_id, :deployment_id, :updates_enabled]
    end

    update :update do
      primary? true
      accept [:description, :deployment_id, :updates_enabled, :updates_blocked_until]
    end

    update :move do
      accept []
      argument :product_id, :integer, allow_nil?: false
      argument :user_id, :integer, allow_nil?: false

      manual fn changeset, _context ->
        product_id = changeset.arguments.product_id
        user_id = changeset.arguments.user_id
        ecto_device = NervesHub.Repo.get!(NervesHub.Devices.Device, changeset.data.id)
        ecto_product = NervesHub.Repo.get!(NervesHub.Products.Product, product_id)
        ecto_user = NervesHub.Repo.get!(NervesHub.Accounts.User, user_id)

        case Devices.move(ecto_device, ecto_product, ecto_user) do
          {:ok, updated} ->
            {:ok, ecto_to_ash(updated)}

          {:error, error} ->
            {:error, error}
        end
      end
    end

    update :enable_updates do
      accept []
      argument :user_id, :integer, allow_nil?: false

      manual fn changeset, _context ->
        ecto_device = NervesHub.Repo.get!(NervesHub.Devices.Device, changeset.data.id)
        ecto_user = NervesHub.Repo.get!(NervesHub.Accounts.User, changeset.arguments.user_id)

        case Devices.enable_updates(ecto_device, ecto_user) do
          {:ok, updated} -> {:ok, ecto_to_ash(updated)}
          {:error, error} -> {:error, error}
        end
      end
    end

    update :disable_updates do
      accept []
      argument :user_id, :integer, allow_nil?: false

      manual fn changeset, _context ->
        ecto_device = NervesHub.Repo.get!(NervesHub.Devices.Device, changeset.data.id)
        ecto_user = NervesHub.Repo.get!(NervesHub.Accounts.User, changeset.arguments.user_id)

        case Devices.disable_updates(ecto_device, ecto_user) do
          {:ok, updated} -> {:ok, ecto_to_ash(updated)}
          {:error, error} -> {:error, error}
        end
      end
    end

    update :clear_penalty_box do
      accept []

      manual fn changeset, _context ->
        ecto_device = NervesHub.Repo.get!(NervesHub.Devices.Device, changeset.data.id)

        case Devices.clear_penalty_box(ecto_device, %{}) do
          {:ok, updated} -> {:ok, ecto_to_ash(updated)}
          {:error, error} -> {:error, error}
        end
      end
    end

    update :restore do
      accept []

      manual fn changeset, _context ->
        ecto_device = NervesHub.Repo.get!(NervesHub.Devices.Device, changeset.data.id)

        case Devices.restore_device(ecto_device) do
          {:ok, updated} -> {:ok, ecto_to_ash(updated)}
          {:error, error} -> {:error, error}
        end
      end
    end

    update :set_as_provisioned do
      accept []

      manual fn changeset, _context ->
        ecto_device = NervesHub.Repo.get!(NervesHub.Devices.Device, changeset.data.id)

        case Devices.set_as_provisioned!(ecto_device) do
          %NervesHub.Devices.Device{} = updated -> {:ok, ecto_to_ash(updated)}
          error -> {:error, error}
        end
      end
    end

    update :update_deployment_group do
      accept []
      argument :deployment_group_id, :integer, allow_nil?: false

      manual fn changeset, _context ->
        ecto_device = NervesHub.Repo.get!(NervesHub.Devices.Device, changeset.data.id)
        deployment_group = NervesHub.Repo.get!(NervesHub.ManagedDeployments.DeploymentGroup, changeset.arguments.deployment_group_id)

        case Devices.update_deployment_group(ecto_device, deployment_group) do
          {:ok, updated} -> {:ok, ecto_to_ash(updated)}
          {:error, error} -> {:error, error}
        end
      end
    end

    update :clear_deployment_group do
      accept []

      manual fn changeset, _context ->
        ecto_device = NervesHub.Repo.get!(NervesHub.Devices.Device, changeset.data.id)

        case Devices.clear_deployment_group(ecto_device) do
          {:ok, updated} -> {:ok, ecto_to_ash(updated)}
          {:error, error} -> {:error, error}
        end
      end
    end

    update :enable_extension do
      accept []
      argument :extension, :string, allow_nil?: false

      manual fn changeset, _context ->
        ecto_device = NervesHub.Repo.get!(NervesHub.Devices.Device, changeset.data.id)

        case Devices.enable_extension_setting(ecto_device, changeset.arguments.extension) do
          {:ok, updated} -> {:ok, ecto_to_ash(updated)}
          {:error, error} -> {:error, error}
        end
      end
    end

    update :disable_extension do
      accept []
      argument :extension, :string, allow_nil?: false

      manual fn changeset, _context ->
        ecto_device = NervesHub.Repo.get!(NervesHub.Devices.Device, changeset.data.id)

        case Devices.disable_extension_setting(ecto_device, changeset.arguments.extension) do
          {:ok, updated} -> {:ok, ecto_to_ash(updated)}
          {:error, error} -> {:error, error}
        end
      end
    end

    update :tag do
      accept []
      argument :tags, {:array, :string}, allow_nil?: false

      manual fn changeset, _context ->
        tags = changeset.arguments.tags
        ecto_device = NervesHub.Repo.get!(NervesHub.Devices.Device, changeset.data.id)

        case Devices.update_device(ecto_device, %{tags: tags}) do
          {:ok, updated} -> {:ok, ecto_to_ash(updated)}
          {:error, error} -> {:error, error}
        end
      end
    end

    update :update_firmware_metadata do
      accept []
      argument :firmware_metadata, :map
      argument :firmware_validation_status, :atom, constraints: [one_of: [:validated, :not_validated, :unknown]]
      argument :firmware_auto_revert_detected, :boolean, default: false

      manual fn changeset, _context ->
        ecto_device = NervesHub.Repo.get!(NervesHub.Devices.Device, changeset.data.id)

        case Devices.update_firmware_metadata(
               ecto_device,
               changeset.arguments[:firmware_metadata],
               changeset.arguments[:firmware_validation_status],
               changeset.arguments[:firmware_auto_revert_detected]
             ) do
          {:ok, updated} -> {:ok, ecto_to_ash(updated)}
          {:error, error} -> {:error, error}
        end
      end
    end

    update :update_network_interface do
      accept []
      argument :network_interface, :string, allow_nil?: false

      manual fn changeset, _context ->
        ecto_device = NervesHub.Repo.get!(NervesHub.Devices.Device, changeset.data.id)

        case Devices.update_network_interface(ecto_device, changeset.arguments.network_interface) do
          {:ok, updated} -> {:ok, ecto_to_ash(updated)}
          {:error, error} -> {:error, error}
        end
      end
    end

    update :firmware_validated do
      accept []

      manual fn changeset, _context ->
        ecto_device = NervesHub.Repo.get!(NervesHub.Devices.Device, changeset.data.id)

        case Devices.firmware_validated(ecto_device) do
          {:ok, updated} -> {:ok, ecto_to_ash(updated)}
          {:error, error} -> {:error, error}
        end
      end
    end

    update :update_blocked_until do
      accept []
      argument :deployment_group_id, :integer, allow_nil?: false

      manual fn changeset, _context ->
        ecto_device = NervesHub.Repo.get!(NervesHub.Devices.Device, changeset.data.id)
        deployment = NervesHub.Repo.get!(NervesHub.ManagedDeployments.DeploymentGroup, changeset.arguments.deployment_group_id)

        case Devices.update_blocked_until(ecto_device, deployment) do
          {:ok, updated} -> {:ok, ecto_to_ash(updated)}
          {:error, error} -> {:error, error}
        end
      end
    end

    update :toggle_updates do
      accept []
      argument :user_id, :integer, allow_nil?: false

      manual fn changeset, _context ->
        ecto_device = NervesHub.Repo.get!(NervesHub.Devices.Device, changeset.data.id)
        ecto_user = NervesHub.Repo.get!(NervesHub.Accounts.User, changeset.arguments.user_id)

        case Devices.toggle_automatic_updates(ecto_device, ecto_user) do
          {:ok, updated} -> {:ok, ecto_to_ash(updated)}
          {:error, error} -> {:error, error}
        end
      end
    end

    destroy :destroy do
      primary? true
      manual fn changeset, _context ->
        ecto_device = NervesHub.Repo.get!(NervesHub.Devices.Device, changeset.data.id)

        case Devices.delete_device(ecto_device) do
          {:ok, _} -> {:ok, changeset.data}
          {:error, error} -> {:error, error}
        end
      end
    end

    destroy :hard_destroy do
      manual fn changeset, _context ->
        ecto_device = NervesHub.Repo.get!(NervesHub.Devices.Device, changeset.data.id)

        case Devices.destroy_device(ecto_device) do
          {:ok, _} -> {:ok, changeset.data}
          {:error, error} -> {:error, error}
        end
      end
    end
  end

  code_interface do
    define :read
    define :get, action: :read, get_by: [:id], not_found_error?: true
    define :list_by_product, args: [:org_id, :product_id]
    define :get_by_identifier, args: [:identifier], get?: true
    define :get_by_org, args: [:org_id, :device_id], get?: true
    define :list_by_org, args: [:org_id]
    define :count_by_org, args: [:org_id]
    define :count_by_product, args: [:product_id]
    define :count_by_org_and_product, args: [:org_id, :product_id]
    define :soft_deleted_exist_for_product, args: [:product_id]
    define :in_penalty_box, args: [:device_id]
    define :has_certificates, args: [:device_id]
    define :create
    define :update
    define :move, args: [:product_id, :user_id]
    define :enable_updates, args: [:user_id]
    define :disable_updates, args: [:user_id]
    define :toggle_updates, args: [:user_id]
    define :clear_penalty_box
    define :restore
    define :set_as_provisioned
    define :firmware_validated
    define :update_deployment_group, args: [:deployment_group_id]
    define :clear_deployment_group
    define :update_blocked_until, args: [:deployment_group_id]
    define :enable_extension, args: [:extension]
    define :disable_extension, args: [:extension]
    define :tag, args: [:tags]
    define :update_firmware_metadata, args: [:firmware_metadata]
    define :update_network_interface, args: [:network_interface]
    define :destroy
    define :hard_destroy
  end

  defp ecto_to_ash(ecto_device) do
    ash_fields = [
      :id, :org_id, :product_id, :deployment_id, :latest_connection_id,
      :latest_health_id, :identifier, :description, :tags, :connecting_code,
      :custom_location_coordinates, :firmware_metadata, :status,
      :firmware_validation_status, :firmware_auto_revert_detected,
      :updates_enabled, :update_attempts, :updates_blocked_until,
      :network_interface, :extensions, :first_seen_at, :deleted_at, :inserted_at, :updated_at
    ]

    attrs = Map.take(ecto_device, ash_fields)

    # firmware_metadata is an embedded Ecto schema - convert to plain map
    attrs =
      case attrs[:firmware_metadata] do
        %NervesHub.Firmwares.FirmwareMetadata{} = fm ->
          Map.put(attrs, :firmware_metadata, Map.from_struct(fm) |> Map.delete(:__meta__))

        _ ->
          attrs
      end

    # extensions is an embedded Ecto schema - convert to plain string-keyed map
    attrs =
      case attrs[:extensions] do
        nil ->
          attrs

        %{__struct__: _} = ext ->
          map =
            ext
            |> Map.from_struct()
            |> Map.delete(:__meta__)
            |> Map.delete(:id)
            |> Enum.into(%{}, fn {k, v} -> {Atom.to_string(k), v} end)

          Map.put(attrs, :extensions, map)

        _ ->
          attrs
      end

    struct!(__MODULE__, attrs)
  end
end

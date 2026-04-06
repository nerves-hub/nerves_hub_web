defmodule NervesHub.Ash.Firmwares.Firmware do
  use Ash.Resource,
    domain: NervesHub.Ash.Firmwares,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  alias NervesHub.Ash.Accounts.Org
  alias NervesHub.Ash.Accounts.OrgKey
  alias NervesHub.Ash.Deployments.DeploymentGroup
  alias NervesHub.Ash.Deployments.DeploymentRelease
  alias NervesHub.Ash.Firmwares.FirmwareDelta
  alias NervesHub.Ash.Products.Product
  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware

  postgres do
    table("firmwares")
    repo(NervesHub.Repo)
  end

  json_api do
    type("firmware")
    derive_filter?(false)

    routes do
      base("/firmwares")

      index(:read)
      index(:list_by_product, route: "/by-product/:product_id")
      index(:list_by_org, route: "/by-org/:org_id")
      get(:read, route: "/:id")
      get(:get_by_product_and_uuid, route: "/by-product/:product_id/uuid/:uuid")
      delete(:destroy)
    end
  end

  graphql do
    encode_primary_key? false
    type(:firmware)

    queries do
      get(:get_firmware, :read)
      list(:list_firmwares, :read)
      list(:list_firmwares_by_product, :list_by_product)
      list(:list_firmwares_by_org, :list_by_org)
      get(:get_firmware_by_product_and_uuid, :get_by_product_and_uuid)
    end

    mutations do
      destroy(:destroy_firmware, :destroy)
    end
  end

  attributes do
    integer_primary_key(:id)

    attribute(:org_id, :integer, allow_nil?: false, public?: true)
    attribute(:product_id, :integer, allow_nil?: false, public?: true)
    attribute(:org_key_id, :integer, public?: true)
    attribute(:architecture, :string, public?: true)
    attribute(:author, :string, public?: true)
    attribute(:description, :string, public?: true)
    attribute(:misc, :string, public?: true)
    attribute(:platform, :string, public?: true)
    attribute(:uuid, :string, allow_nil?: false, public?: true)
    attribute(:version, :string, public?: true)
    attribute(:vcs_identifier, :string, public?: true)
    attribute(:size, :integer, public?: true)
    attribute(:tool, :string, public?: true)
    attribute(:tool_delta_required_version, :string, public?: true)
    attribute(:tool_full_required_version, :string, public?: true)
    attribute(:tool_metadata, :map, public?: true)
    attribute(:upload_metadata, :map, public?: true)
    attribute(:delta_updatable, :boolean, default: false, public?: true)

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :org, Org do
      public?(true)
      source_attribute(:org_id)
      destination_attribute(:id)
    end

    belongs_to :product, Product do
      public?(true)
      source_attribute(:product_id)
      destination_attribute(:id)
    end

    belongs_to :org_key, OrgKey do
      public?(true)
      source_attribute(:org_key_id)
      destination_attribute(:id)
    end

    has_many :deployment_groups, DeploymentGroup do
      public?(true)
      source_attribute(:id)
      destination_attribute(:firmware_id)
    end

    has_many :deployment_releases, DeploymentRelease do
      public?(true)
      source_attribute(:id)
      destination_attribute(:firmware_id)
    end

    has_many :firmware_deltas_as_source, FirmwareDelta do
      public?(true)
      source_attribute(:id)
      destination_attribute(:source_id)
    end

    has_many :firmware_deltas_as_target, FirmwareDelta do
      public?(true)
      source_attribute(:id)
      destination_attribute(:target_id)
    end
  end

  actions do
    defaults([:read])

    read :list_by_product do
      argument(:product_id, :integer, allow_nil?: false)

      filter(expr(product_id == ^arg(:product_id)))
    end

    read :list_by_org do
      argument(:org_id, :integer, allow_nil?: false)

      filter(expr(org_id == ^arg(:org_id)))
    end

    read :get_by_product_and_uuid do
      argument(:product_id, :integer, allow_nil?: false)
      argument(:uuid, :string, allow_nil?: false)

      filter(expr(product_id == ^arg(:product_id) and uuid == ^arg(:uuid)))
    end

    read :get_by_platform_and_architecture do
      argument :product_id, :integer, allow_nil?: false
      argument :platform, :string, allow_nil?: false
      argument :architecture, :string, allow_nil?: false

      filter expr(product_id == ^arg(:product_id) and platform == ^arg(:platform) and architecture == ^arg(:architecture))
    end

    action :count_by_product, :integer do
      argument :product_id, :integer, allow_nil?: false

      run fn input, _context ->
        product = %NervesHub.Products.Product{id: input.arguments.product_id}
        {:ok, Firmwares.count(product)}
      end
    end

    action :unique_platforms, {:array, :string} do
      argument :product_id, :integer, allow_nil?: false

      run fn input, _context ->
        product = %NervesHub.Products.Product{id: input.arguments.product_id}
        {:ok, Firmwares.get_unique_platforms(product)}
      end
    end

    action :unique_architectures, {:array, :string} do
      argument :product_id, :integer, allow_nil?: false

      run fn input, _context ->
        product = %NervesHub.Products.Product{id: input.arguments.product_id}
        {:ok, Firmwares.get_unique_architectures(product)}
      end
    end

    action :versions_by_product, {:array, :string} do
      argument :product_id, :integer, allow_nil?: false

      run fn input, _context ->
        {:ok, Firmwares.get_firmware_versions_by_product(input.arguments.product_id)}
      end
    end

    read :get_for_device do
      argument :platform, :string, allow_nil?: false
      argument :architecture, :string, allow_nil?: false
      argument :org_id, :integer, allow_nil?: false
      argument :product_id, :integer, allow_nil?: false

      filter expr(
        platform == ^arg(:platform) and
        architecture == ^arg(:architecture) and
        org_id == ^arg(:org_id) and
        product_id == ^arg(:product_id)
      )
    end

    create :create do
      accept [
        :org_id, :product_id, :org_key_id, :architecture, :author, :description,
        :misc, :platform, :uuid, :version, :vcs_identifier, :size, :tool,
        :tool_delta_required_version, :tool_full_required_version, :tool_metadata,
        :upload_metadata, :delta_updatable
      ]
    end

    destroy :destroy do
      primary? true
      manual(fn changeset, _context ->
        ecto_firmware = NervesHub.Repo.get!(Firmware, changeset.data.id)

        case Firmwares.delete_firmware(ecto_firmware) do
          {:ok, _} -> {:ok, changeset.data}
          {:error, error} -> {:error, error}
        end
      end)
    end
  end

  code_interface do
    define :read
    define :get, action: :read, get_by: [:id], not_found_error?: true
    define :list_by_product, args: [:product_id]
    define :list_by_org, args: [:org_id]
    define :get_by_product_and_uuid, args: [:product_id, :uuid], get?: true
    define :get_by_platform_and_architecture, args: [:product_id, :platform, :architecture]
    define :count_by_product, args: [:product_id]
    define :unique_platforms, args: [:product_id]
    define :unique_architectures, args: [:product_id]
    define :versions_by_product, args: [:product_id]
    define :get_for_device, args: [:platform, :architecture, :org_id, :product_id]
    define :create
    define :destroy
  end
end

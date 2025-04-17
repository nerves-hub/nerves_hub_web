defmodule NervesHub.Firmwares.Firmware do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgKey
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Products.Product

  alias __MODULE__

  @type t :: %Firmware{
          architecture: String.t(),
          author: String.t() | nil,
          description: String.t() | nil,
          misc: String.t() | nil,
          platform: String.t(),
          product: Ecto.Association.NotLoaded.t() | Product.t(),
          uuid: Ecto.UUID.t(),
          vcs_identifier: String.t() | nil,
          version: Version.build()
        }

  @optional_params [
    :author,
    :delta_updatable,
    :description,
    :misc,
    :org_key_id,
    :vcs_identifier
  ]

  @required_params [
    :architecture,
    :org_id,
    :platform,
    :product_id,
    :size,
    :upload_metadata,
    :uuid,
    :version
  ]

  @derive {Phoenix.Param, key: :uuid}
  schema "firmwares" do
    belongs_to(:org, Org, where: [deleted_at: nil])
    belongs_to(:product, Product, where: [deleted_at: nil])
    belongs_to(:org_key, OrgKey)
    has_many(:deployment_groups, DeploymentGroup)

    field(:architecture, :string)
    field(:author, :string)
    field(:delta_updatable, :boolean, default: false)
    field(:description, :string)
    field(:misc, :string)
    field(:platform, :string)
    field(:size, :integer)
    field(:upload_metadata, :map)
    field(:uuid, :string)
    field(:vcs_identifier, :string)
    field(:version, :string)

    field(:install_count, :integer, virtual: true)

    timestamps()
  end

  def create_changeset(%Firmware{} = firmware, params) do
    firmware
    |> cast(params, @required_params ++ @optional_params)
    |> validate_required(@required_params)
    |> unique_constraint(:uuid, name: :firmwares_product_id_uuid_index)
    |> foreign_key_constraint(:deployment_groups, name: :deployment_groups_firmware_id_fkey)
  end

  def update_changeset(%Firmware{} = firmware, params) do
    firmware
    |> cast(params, @required_params ++ @optional_params)
    |> validate_required(@required_params)
    |> unique_constraint(:uuid, name: :firmwares_product_id_uuid_index)
    |> foreign_key_constraint(:deployment_groups, name: :deployment_groups_firmware_id_fkey)
  end

  def delete_changeset(%Firmware{} = firmware, params) do
    firmware
    |> cast(params, @required_params ++ @optional_params)
    |> no_assoc_constraint(:deployment_groups, message: "Firmware has associated deployments")
  end
end

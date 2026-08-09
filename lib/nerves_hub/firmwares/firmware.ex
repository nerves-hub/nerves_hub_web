defmodule NervesHub.Firmwares.Firmware do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias __MODULE__
  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgKey
  alias NervesHub.ManagedDeployments.DeploymentRelease
  alias NervesHub.Products.Product
  alias NervesHub.Repo

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
    :tool,
    :tool_delta_required_version,
    :tool_full_required_version,
    :tool_metadata,
    :upload_metadata,
    :uuid,
    :version
  ]

  @derive {Phoenix.Param, key: :uuid}
  schema "firmwares" do
    belongs_to(:org, Org, where: [deleted_at: nil])
    belongs_to(:product, Product, where: [deleted_at: nil])
    belongs_to(:org_key, OrgKey)

    has_many(:deployment_releases, DeploymentRelease)

    field(:architecture, :string)
    field(:author, :string)
    field(:delta_updatable, :boolean, default: false)
    field(:description, :string)
    field(:misc, :string)
    field(:platform, :string)
    field(:size, :integer)
    field(:tool, :string, default: "fwup")
    # Which version of the tool is required for delta updates
    field(:tool_delta_required_version, :string)
    # Which version of the tool is required for full updates
    field(:tool_full_required_version, :string)
    # Other values that the tool usage might care about
    # that don't seem likely to be the same between different firmware update tools
    field(:tool_metadata, :map)

    field(:upload_metadata, :map)
    field(:uuid, :string)
    field(:vcs_identifier, :string)
    field(:version, :string)

    field(:checksum, :string)
    field(:partials_checksums, {:array, :string}, default: [])

    field(:install_count, :integer, virtual: true)

    timestamps()
  end

  def create_changeset(%Firmware{} = firmware, params) do
    firmware
    |> cast(params, @required_params ++ @optional_params ++ [:checksum, :partials_checksums])
    |> validate_required(@required_params)
    |> validate_semver_version()
    |> validate_unique_version(params)
    |> unique_constraint(:uuid, name: :firmwares_product_id_uuid_index)
    |> foreign_key_constraint(:deployment_groups, name: :deployment_groups_firmware_id_fkey)
  end

  def update_changeset(%Firmware{} = firmware, params) do
    firmware
    |> cast(params, @required_params ++ @optional_params)
    |> validate_required(@required_params)
    |> validate_semver_version()
    |> unique_constraint(:uuid, name: :firmwares_product_id_uuid_index)
    |> foreign_key_constraint(:deployment_groups, name: :deployment_groups_firmware_id_fkey)
  end

  # Firmware versions must be valid SemVer: they feed `semver_sort_key/1` for
  # ordering and version-constrained deployment matching, and `Version.parse/1`
  # is the single parsing authority those paths rely on.
  defp validate_semver_version(changeset) do
    validate_change(changeset, :version, fn :version, version ->
      case Version.parse(version) do
        {:ok, _} -> []
        :error -> [version: "must be a valid semantic version"]
      end
    end)
  end

  # When the product requires unique firmware versions (passed through `params`
  # from the product's setting), reject a version that already exists for the
  # same product/platform/architecture. The same version built for a different
  # target is still allowed. This is an application-level check rather than a
  # unique index because the requirement is a per-product toggle; two
  # truly-concurrent uploads of the same version leave a small race window that
  # the check does not close.
  defp validate_unique_version(changeset, params) do
    if changeset.valid? and require_unique_version?(params) and version_taken?(changeset) do
      add_error(changeset, :version, "has already been taken for this product")
    else
      changeset
    end
  end

  defp require_unique_version?(params) do
    params[:require_unique_firmware_version] == true or
      params["require_unique_firmware_version"] == true
  end

  defp version_taken?(changeset) do
    product_id = get_field(changeset, :product_id)
    platform = get_field(changeset, :platform)
    architecture = get_field(changeset, :architecture)
    version = get_field(changeset, :version)

    Firmware
    |> where(
      [f],
      f.product_id == ^product_id and f.platform == ^platform and
        f.architecture == ^architecture and f.version == ^version
    )
    |> Repo.exists?()
  end

  def delete_changeset(%Firmware{} = firmware) do
    firmware
    |> change()
    |> no_assoc_constraint(:deployment_releases, message: "Firmware has associated deployment releases")
  end
end

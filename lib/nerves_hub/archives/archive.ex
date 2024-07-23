defmodule NervesHub.Archives.Archive do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.OrgKey
  alias NervesHub.Products.Product
  alias NervesHub.Fwup.Metadata

  @type t :: %__MODULE__{
          architecture: String.t(),
          author: String.t() | nil,
          description: String.t() | nil,
          misc: String.t() | nil,
          org_key: Ecto.Association.NotLoaded.t() | OrgKey.t(),
          platform: String.t(),
          product: Ecto.Association.NotLoaded.t() | Product.t(),
          size: pos_integer(),
          uuid: Ecto.UUID.t(),
          vcs_identifier: String.t() | nil,
          version: Version.build()
        }

  schema "archives" do
    belongs_to(:product, Product, where: [deleted_at: nil])
    belongs_to(:org_key, OrgKey)

    field(:size, :integer)

    field(:architecture, :string)
    field(:author, :string)
    field(:description, :string)
    field(:misc, :string)
    field(:platform, :string)
    field(:uuid, Ecto.UUID)
    field(:version, :string)
    field(:vcs_identifier, :string)

    timestamps()
  end

  def create_changeset(archive, %Metadata{} = metadata) do
    create_changeset(archive, Map.from_struct(metadata))
  end

  def create_changeset(archive, params) do
    archive
    |> cast(params, [
      :size,
      :architecture,
      :author,
      :description,
      :misc,
      :platform,
      :uuid,
      :version,
      :vcs_identifier
    ])
    |> validate_required([
      :product_id,
      :org_key_id,
      :size,
      :architecture,
      :platform,
      :uuid,
      :version
    ])
    |> unique_constraint(:uuid, name: :archives_product_id_uuid_index)
    |> foreign_key_constraint(:products)
  end
end

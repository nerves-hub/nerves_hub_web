defmodule NervesHub.Archives.Archive do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.OrgKey
  alias NervesHub.Products.Product

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

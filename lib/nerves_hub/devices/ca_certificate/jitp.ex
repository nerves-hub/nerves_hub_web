defmodule NervesHub.Devices.CACertificate.JITP do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias NervesHub.Types.Tag

  schema "jitp" do
    # JITP enabled CA Certs must be linked to a product
    # so devices can be created
    belongs_to(:product, Product)

    # Will be copied to the device when it's created. Optional: a device
    # can start out with no tags and no description.
    field(:tags, Tag)
    field(:description, :string)
    timestamps()
  end

  def changeset(jitp, %{"delete" => "true"}, _org_id) do
    %{change(jitp) | action: :delete}
  end

  def changeset(jitp, params, org_id) do
    jitp
    |> cast(params, [:tags, :description, :product_id])
    |> validate_required([:product_id])
    |> validate_product_in_org(org_id)
  end

  # Devices provisioned by the CA are created in the CA's org with this product,
  # so the product has to be one of that org's. Otherwise a CA could put its
  # devices into another org's product, where they'd be offered its firmware.
  defp validate_product_in_org(changeset, org_id) do
    validate_change(changeset, :product_id, fn :product_id, product_id ->
      Product
      |> where(id: ^product_id, org_id: ^org_id)
      |> Repo.exclude_deleted()
      |> Repo.exists?()
      |> if(do: [], else: [product_id: "must be a product in this organization"])
    end)
  end
end

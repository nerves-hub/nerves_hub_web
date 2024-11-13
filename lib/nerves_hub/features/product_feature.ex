defmodule NervesHub.Features.ProductFeature do
  use Ecto.Schema

  alias Ecto.Changeset
  alias NervesHub.Features.Feature
  alias NervesHub.Products.Product

  schema "product_features" do
    belongs_to(:feature, Feature)
    belongs_to(:product, Product)

    field(:allowed, :boolean, default: false)
  end

  def changeset(product_feature \\ %__MODULE__{}, attrs) do
    product_feature
    |> Changeset.cast(attrs, [:allowed, :feature_id, :product_id])
    |> Changeset.validate_required([:allowed, :feature_id, :product_id])
  end
end

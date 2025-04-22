defmodule NervesHub.Devices.CACertificate.JITP do
  use Ecto.Schema
  import Ecto.Changeset
  alias NervesHub.Products.Product

  schema "jitp" do
    # JITP enabled CA Certs must be linked to a product
    # so devices can be created
    belongs_to(:product, Product)

    # Will be copied to the device when it's created
    field(:tags, NervesHub.Types.Tag)
    field(:description, :string)
    timestamps()
  end

  def changeset(jitp, %{"delete" => "true"}) do
    %{change(jitp) | action: :delete}
  end

  def changeset(jitp, params) do
    jitp
    |> cast(params, [:tags, :description, :product_id])
    |> validate_required([:tags, :description, :product_id])
  end
end

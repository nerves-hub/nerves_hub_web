defmodule NervesHubWebCore.Devices.CACertificate.JITP do
  use Ecto.Schema
  import Ecto.Changeset
  alias NervesHubWebCore.Products.Product

  schema "jitp" do
    # JITP enabled CA Certs must be linked to a product
    # so devices can be created
    belongs_to(:product, Product)

    # Will be coppied to the device when it's created
    field(:tags, NervesHubWebCore.Types.Tag)
    field(:description, :string)
    timestamps()
  end

  def changeset(jitp, params) do
    jitp
    |> cast(params, [:tags, :description])
    |> validate_required([:tags, :description])
  end
end

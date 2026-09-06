defmodule NervesHub.Products.HealthProfile do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Products.HealthProfileMetric
  alias NervesHub.Products.Product

  @type t :: %__MODULE__{}

  schema "health_profiles" do
    belongs_to(:product, Product)

    # nil means this is the product's default profile; a value scopes the
    # profile to devices whose firmware reports that platform.
    field(:platform, :string)

    has_many(:metrics, HealthProfileMetric, preload_order: [asc: :key])

    timestamps()
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [:product_id, :platform])
    |> validate_required([:product_id])
    |> update_change(:platform, &trim_to_nil/1)
    |> foreign_key_constraint(:product_id)
    |> unique_constraint(:platform,
      name: :health_profiles_product_id_platform_index,
      message: "already has a health profile"
    )
  end

  defp trim_to_nil(nil), do: nil

  defp trim_to_nil(platform) do
    case String.trim(platform) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end

defmodule NervesHub.Products.CustomHealthMetricsLabel do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Products.Product

  @type t :: %__MODULE__{}

  @required [:product_id, :key, :label]

  schema "custom_health_metrics_labels" do
    belongs_to(:product, Product)

    field(:key, :string)
    field(:label, :string)

    timestamps()
  end

  def changeset(struct, params) do
    struct
    |> cast(params, @required)
    |> validate_required(@required)
    |> validate_length(:label, min: 1, max: 255)
    |> foreign_key_constraint(:product_id)
    |> unique_constraint([:product_id, :key])
  end
end

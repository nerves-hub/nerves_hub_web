defmodule NervesHub.Products.ProductApiKey do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Products.Product

  @type t :: %__MODULE__{}

  @key_prefix "nhp_api"

  schema "product_api_keys" do
    belongs_to(:product, Product)

    field(:key, :string)
    field(:name, :string)

    field(:deactivated_at, :utc_datetime)

    timestamps()
  end

  def create_changeset(%Product{} = product, attrs \\ %{}) do
    change(%__MODULE__{}, product_id: product.id)
    |> cast(attrs, [:name])
    |> put_change(:key, "#{@key_prefix}_#{generate_token()}")
    |> validate_required([:product_id, :key, :name])
    |> validate_format(:key, ~r/^#{@key_prefix}_[a-zA-Z0-9\-\/\+]{171}$/)
    |> foreign_key_constraint(:product_id)
    |> unique_constraint(:key)
  end

  def deactivate_changeset(%__MODULE__{} = api_key) do
    change(api_key)
    |> put_change(:deactivated_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  defp generate_token() do
    :crypto.strong_rand_bytes(128) |> Base.encode64(padding: false)
  end
end

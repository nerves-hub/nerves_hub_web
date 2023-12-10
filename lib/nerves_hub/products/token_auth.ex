defmodule NervesHub.Products.TokenAuth do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Products.Product

  @type t :: %__MODULE__{}

  @access_id_prefix "nhp"

  schema "product_auth_tokens" do
    belongs_to(:product, Product)

    field(:access_id, :string)
    field(:secret, :string)

    field(:deactivated_at, :utc_datetime)

    timestamps()
  end

  def create_changeset(%Product{} = product) do
    change(%__MODULE__{}, product_id: product.id)
    |> put_change(:access_id, "#{@access_id_prefix}_#{generate_token()}")
    |> put_change(:secret, generate_token())
    |> validate_required([:product_id, :access_id, :secret])
    |> validate_format(:access_id, ~r/^nhp_[a-zA-Z0-9\-\/\+]{43}$/)
    |> validate_format(:secret, ~r/^[a-zA-Z0-9\-\/\+]{43}$/)
    |> foreign_key_constraint(:product_id)
    |> unique_constraint(:access_id)
    |> unique_constraint(:secret)
  end

  defp generate_token() do
    :crypto.strong_rand_bytes(32) |> Base.encode64(padding: false)
  end
end

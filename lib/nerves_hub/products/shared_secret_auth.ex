defmodule NervesHub.Products.SharedSecretAuth do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Products.Product

  @type t :: %__MODULE__{}

  @key_prefix "nhp"

  schema "product_shared_secret_auth" do
    belongs_to(:product, Product)

    field(:key, :string)
    field(:secret, :string)

    field(:deactivated_at, :utc_datetime)

    timestamps()
  end

  def create_changeset(%Product{} = product) do
    change(%__MODULE__{}, product_id: product.id)
    |> put_change(:key, "#{@key_prefix}_#{generate_token()}")
    |> put_change(:secret, generate_token())
    |> validate_required([:product_id, :key, :secret])
    |> validate_format(:key, ~r/^#{@key_prefix}_[a-zA-Z0-9\-\/\+]{43}$/)
    |> validate_format(:secret, ~r/^[a-zA-Z0-9\-\/\+]{43}$/)
    |> foreign_key_constraint(:product_id)
    |> unique_constraint(:key)
    |> unique_constraint(:secret)
  end

  def deactivate_changeset(%__MODULE__{} = auth) do
    change(auth)
    |> put_change(:deactivated_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  defp generate_token() do
    :crypto.strong_rand_bytes(32) |> Base.encode64(padding: false)
  end
end

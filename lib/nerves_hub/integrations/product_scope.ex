defmodule NervesHub.Integrations.ProductScope do
  @moduledoc """
  The products an integration hears: every product in its organization
  (`all_products`), including products added later, or the ones it lists.
  Webhooks and Slack channels both work this way.

  A change names products by name, as the API knows them, and they are looked
  up among the organization's own products here. Nothing takes a product
  handed to it, which is what keeps an integration from hearing another
  organization's devices.
  """

  import Ecto.Changeset
  import Ecto.Query

  alias NervesHub.Accounts.Org
  alias NervesHub.Products.Product
  alias NervesHub.Repo

  @typedoc """
  The products a change names, as `find_products/2` found them in the
  organization: those it found, and the names it did not. `nil` when the
  change names no products, which leaves them as they are.
  """
  @type found() :: {[Product.t()], [String.t()]} | :invalid | nil

  @doc """
  Naming products is asking for those products, so attributes that list them
  without saying `all_products` mean `all_products: false`. Only
  string-keyed attributes name products: they come from a form or the API.
  """
  @spec normalize_attrs(map()) :: map()
  def normalize_attrs(%{"products" => _} = attrs) when not is_map_key(attrs, "all_products") do
    Map.put(attrs, "all_products", false)
  end

  def normalize_attrs(attrs), do: attrs

  @doc "Looks up the products `attrs` name among the organization's own."
  @spec find_products(Org.t(), map()) :: found()
  def find_products(%Org{id: org_id}, %{"products" => names}) when is_list(names) do
    if Enum.all?(names, &is_binary/1) do
      names = Enum.uniq(names)

      products =
        Product
        |> where([p], p.org_id == ^org_id and p.name in ^names)
        |> Repo.exclude_deleted()
        |> order_by(:name)
        |> Repo.all()

      found = MapSet.new(products, & &1.name)
      {products, Enum.reject(names, &MapSet.member?(found, &1))}
    else
      :invalid
    end
  end

  def find_products(_org, %{"products" => _not_a_list}), do: :invalid
  def find_products(_org, _attrs), do: nil

  @doc """
  Puts the products a change named on an integration's changeset, which has
  cast `all_products` and whose `products` are loaded.

  An integration for every product keeps no list, so that limiting it later
  starts from an empty choice rather than a forgotten one, and names the
  change carries are not looked at.
  """
  @spec put(Ecto.Changeset.t(), found()) :: Ecto.Changeset.t()
  def put(changeset, found) do
    if get_field(changeset, :all_products) do
      put_assoc(changeset, :products, [])
    else
      changeset
      |> put_products(found)
      |> require_products()
    end
  end

  defp put_products(changeset, nil), do: changeset
  defp put_products(changeset, :invalid), do: add_error(changeset, :products, "must be a list of product names")
  defp put_products(changeset, {products, []}), do: put_assoc(changeset, :products, products)

  defp put_products(changeset, {_products, unknown}) do
    add_error(changeset, :products, "has no product named #{Enum.join(unknown, ", ")}")
  end

  defp require_products(changeset) do
    if is_nil(changeset.errors[:products]) and get_field(changeset, :products) == [] do
      add_error(changeset, :products, "choose at least one product")
    else
      changeset
    end
  end

  @doc """
  The ids of the products an integration hears, deleted products aside:
  every product of `org_id` when `all_products`, otherwise those listed in
  `join_table` against `owner_key` = `owner_id`.
  """
  @spec heard_product_ids(pos_integer(), boolean(), String.t(), atom(), pos_integer()) :: [pos_integer()]
  def heard_product_ids(org_id, true = _all_products, _join_table, _owner_key, _owner_id) do
    Product
    |> where(org_id: ^org_id)
    |> Repo.exclude_deleted()
    |> select([p], p.id)
    |> Repo.all()
  end

  def heard_product_ids(_org_id, false, join_table, owner_key, owner_id) do
    from(j in join_table,
      join: p in Product,
      on: p.id == j.product_id,
      where: field(j, ^owner_key) == ^owner_id and is_nil(p.deleted_at),
      select: p.id
    )
    |> Repo.all()
  end
end

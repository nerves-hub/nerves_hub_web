defmodule NervesHub.Access do
  import Ecto.Query

  alias NervesHub.Archives.Archive
  alias NervesHub.Products.Product
  alias NervesHub.Scripts.Script
  alias NervesHub.Repo

  @doc """
  Check if an org owns an Archive by joining through Product.
  """
  def org_owns_archive?(org_id, %Archive{product_id: product_id}) do
    Repo.exists?(
      from(p in Product,
        where: p.id == ^product_id and p.org_id == ^org_id and is_nil(p.deleted_at)
      )
    )
  end

  @doc """
  Check if an org owns a Script by joining through Product.
  """
  def org_owns_script?(org_id, %Script{product_id: product_id}) do
    Repo.exists?(
      from(p in Product,
        where: p.id == ^product_id and p.org_id == ^org_id and is_nil(p.deleted_at)
      )
    )
  end
end

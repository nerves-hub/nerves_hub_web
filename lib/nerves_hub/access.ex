defmodule NervesHub.Access do
  import Ecto.Query

  alias NervesHub.Archives.Archive
  alias NervesHub.Devices.Device
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias NervesHub.Scripts.Script

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

  @doc """
  Check that ALL device IDs in the list belong to the given org.
  Returns true only if every ID exists and has a matching org_id.
  """
  def org_owns_devices?(org_id, device_ids) when is_list(device_ids) do
    count =
      from(d in Device,
        where: d.id in ^device_ids and d.org_id == ^org_id,
        select: count(d.id)
      )
      |> Repo.one()

    count == length(device_ids)
  end
end

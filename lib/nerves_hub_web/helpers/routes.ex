defmodule NervesHubWeb.Helpers.Hashids do
  def hashid(%NervesHub.Products.Product{} = product) do
    hashid = Application.get_env(:nerves_hub, :hashid_for_products)
    Hashids.encode(hashid, [product.id])
  end

  def hashid(%NervesHub.Accounts.Org{} = org) do
    hashid = Application.get_env(:nerves_hub, :hashid_for_orgs)
    Hashids.encode(hashid, [org.id])
  end
end

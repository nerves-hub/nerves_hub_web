defmodule NervesHubWeb.OrgView do
  use NervesHubWeb, :view

  import NervesHubWeb.LayoutView, only: [user_org_products: 2]

  def count_org_products(user, org) do
    Enum.count(user_org_products(user, org))
  end
end

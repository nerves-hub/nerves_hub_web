defmodule NervesHubWWWWeb.OrgView do
  use NervesHubWWWWeb, :view

  import NervesHubWWWWeb.LayoutView, only: [humanize_size: 1, humanize_seconds: 1, user_org_products: 2]
  
  def count_org_products(user, org) do
    Enum.count(user_org_products(user, org))
  end
end

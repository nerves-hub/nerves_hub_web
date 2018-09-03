defmodule NervesHubWWWWeb.DashboardView do
  use NervesHubWWWWeb, :view

  def dashboard_row_class(current_product, selected_product) do
    if current_product.id == selected_product.id do
      "list-group-item selected"
    else
      "list-group-item"
    end
  end
end

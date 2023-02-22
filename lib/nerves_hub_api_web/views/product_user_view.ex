defmodule NervesHubAPIWeb.ProductUserView do
  use NervesHubAPIWeb, :view
  alias NervesHubAPIWeb.ProductUserView

  def render("index.json", %{product_users: product_users}) do
    %{data: render_many(product_users, ProductUserView, "product_user.json")}
  end

  def render("show.json", %{product_user: product_user}) do
    %{data: render_one(product_user, ProductUserView, "product_user.json")}
  end

  def render("product_user.json", %{product_user: product_user}) do
    %{
      username: product_user.user.username,
      email: product_user.user.email,
      role: product_user.role
    }
  end
end

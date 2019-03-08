defmodule NervesHubWebCore.Products.ProductUser do
  use Ecto.Schema

  alias NervesHubWebCore.Accounts.User
  alias NervesHubWebCore.Products.Product

  schema "product_users" do
    belongs_to(:product, Product)
    belongs_to(:user, User)

    field(:role, User.Role)

    timestamps()
  end
end

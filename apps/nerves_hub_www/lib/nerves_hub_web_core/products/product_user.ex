defmodule NervesHubWebCore.Products.ProductUser do
  use Ecto.Schema

  import Ecto.Query

  alias NervesHubWebCore.Products.Product
  alias NervesHubWebCore.Accounts.User

  schema "product_users" do
    belongs_to(:product, Product, where: [deleted_at: nil])
    belongs_to(:user, User, where: [deleted_at: nil])

    field(:role, User.Role)

    timestamps()
  end

  def with_user(query) do
    preload(query, :user)
  end
end

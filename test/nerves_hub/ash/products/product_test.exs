defmodule NervesHub.Ash.Products.ProductTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Ash.Products.Product
  alias NervesHub.Fixtures

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    %{user: user, org: org, product: product}
  end

  describe "read" do
    test "default read returns products", %{product: product} do
      products = Product.read!()
      assert Enum.any?(products, &(&1.id == product.id))
    end

    test "get by id", %{product: product} do
      found = Product.get!(product.id)
      assert found.id == product.id
      assert found.name == product.name
    end

    test "list_by_org returns products for org", %{org: org, product: product} do
      products = Product.list_by_org!(org.id)
      assert Enum.any?(products, &(&1.id == product.id))
    end

    test "list_by_org excludes soft-deleted products", %{user: user, org: org} do
      product2 = Fixtures.product_fixture(user, org)

      NervesHub.Products.delete_product(
        NervesHub.Repo.get!(NervesHub.Products.Product, product2.id)
      )

      products = Product.list_by_org!(org.id)
      refute Enum.any?(products, &(&1.id == product2.id))
    end

    test "get_by_org_and_name returns matching product", %{org: org, product: product} do
      found = Product.get_by_org_and_name!(org.id, product.name)
      assert found.id == product.id
    end
  end

  describe "create" do
    test "creates product with valid params", %{org: org} do
      product =
        Product.create!(%{
          name: "ash-test-product-#{System.unique_integer([:positive])}",
          org_id: org.id
        })

      assert product.id
      assert product.org_id == org.id
    end
  end

  describe "update" do
    test "updates product name", %{product: product} do
      ash_product = Product.get!(product.id)
      updated = Product.update!(ash_product, %{name: "updated-name"})
      assert updated.name == "updated-name"
    end
  end

  describe "enable_extension / disable_extension" do
    test "enables and disables extension", %{product: product} do
      ash_product = Product.get!(product.id)

      enabled = Product.enable_extension!(ash_product, "health")
      assert enabled.extensions["health"] == true

      disabled = Product.disable_extension!(enabled, "health")
      assert disabled.extensions["health"] == false
    end
  end

  describe "count_by_org" do
    test "returns product count for org", %{org: org} do
      count = Product.count_by_org!(org.id)
      assert is_integer(count)
      assert count >= 1
    end
  end

  describe "destroy" do
    test "soft-deletes product", %{user: user, org: org} do
      product = Fixtures.product_fixture(user, org, %{name: "to-delete"})
      ash_product = Product.get!(product.id)

      :ok = Product.destroy!(ash_product)

      products = Product.list_by_org!(org.id)
      refute Enum.any?(products, &(&1.id == product.id))
    end
  end
end

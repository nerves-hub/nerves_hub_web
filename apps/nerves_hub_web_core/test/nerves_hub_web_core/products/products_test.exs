defmodule NervesHubWebCore.ProductsTest do
  use NervesHubWebCore.DataCase, async: true

  alias NervesHubWebCore.Fixtures
  alias NervesHubWebCore.Products

  describe "products" do
    alias NervesHubWebCore.Products.Product

    @valid_attrs %{name: "some name"}
    @update_attrs %{name: "some updated name"}
    @invalid_attrs %{name: nil}

    setup do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)
      product = Fixtures.product_fixture(org, %{name: "a product"})

      {:ok, %{product: product, org: org}}
    end

    test "list_products/0 returns all products", %{product: product, org: org} do
      assert Products.list_products(org) == [product]
    end

    test "get_product!/1 returns the product with given id", %{product: product} do
      assert Products.get_product!(product.id) == product
    end

    test "create_product/1 with valid data creates a product", %{org: org} do
      assert {:ok, %Product{} = product} =
               %{org_id: org.id}
               |> Enum.into(@valid_attrs)
               |> Products.create_product()

      assert product.name == "some name"
    end

    test "create_product/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Products.create_product(@invalid_attrs)
    end

    test "create_product/1 fails with duplicate names", %{org: org} do
      {:ok, _product} =
        %{org_id: org.id}
        |> Enum.into(%{name: "same name"})
        |> Products.create_product()

      assert {:error, %Ecto.Changeset{}} =
               %{org_id: org.id}
               |> Enum.into(%{name: "same name"})
               |> Products.create_product()
    end

    test "update_product/2 with valid data updates the product", %{product: product} do
      assert {:ok, %Product{} = product} = Products.update_product(product, @update_attrs)

      assert product.name == "some updated name"
    end

    test "update_product/2 with invalid data returns error changeset", %{product: product} do
      assert {:error, %Ecto.Changeset{}} = Products.update_product(product, @invalid_attrs)
      assert product == Products.get_product!(product.id)
    end

    test "delete_product/1 deletes the product", %{product: product} do
      assert {:ok, %Product{}} = Products.delete_product(product)
      assert_raise Ecto.NoResultsError, fn -> Products.get_product!(product.id) end
    end

    test "change_product/1 returns a product changeset", %{product: product} do
      assert %Ecto.Changeset{} = Products.change_product(product)
    end
  end
end

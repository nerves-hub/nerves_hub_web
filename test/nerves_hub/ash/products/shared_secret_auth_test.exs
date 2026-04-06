defmodule NervesHub.Ash.Products.SharedSecretAuthTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Ash.Products.SharedSecretAuth
  alias NervesHub.Fixtures

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    %{user: user, org: org, product: product}
  end

  describe "create" do
    test "creates shared secret auth for product", %{product: product} do
      auth = SharedSecretAuth.create!(%{product_id: product.id})

      assert auth.id
      assert auth.product_id == product.id
      assert auth.key != nil
      assert auth.secret != nil
      assert auth.deactivated_at == nil
    end
  end

  describe "list_by_product" do
    test "returns auths for product", %{product: product} do
      SharedSecretAuth.create!(%{product_id: product.id})

      auths = SharedSecretAuth.list_by_product!(product.id)

      assert length(auths) >= 1
      assert Enum.all?(auths, &(&1.product_id == product.id))
    end
  end

  describe "get_by_key" do
    test "finds active auth by key", %{product: product} do
      auth = SharedSecretAuth.create!(%{product_id: product.id})

      found = SharedSecretAuth.get_by_key!(auth.key)

      assert found.id == auth.id
    end
  end

  describe "deactivate" do
    test "deactivates shared secret auth", %{product: product} do
      auth = SharedSecretAuth.create!(%{product_id: product.id})

      deactivated = SharedSecretAuth.deactivate!(auth)
      assert deactivated.deactivated_at != nil

      # Deactivated auth should not be found by get_by_key
      assert {:error, _} = SharedSecretAuth.get_by_key(auth.key)
    end
  end

  describe "destroy" do
    test "deletes shared secret auth", %{product: product} do
      auth = SharedSecretAuth.create!(%{product_id: product.id})

      assert :ok = SharedSecretAuth.destroy!(auth)
    end
  end
end

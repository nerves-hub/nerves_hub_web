defmodule NervesHub.ScriptsTest do
  use NervesHub.DataCase

  alias NervesHub.Fixtures
  alias NervesHub.Scripts

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)

    %{user: user, org: org, product: product}
  end

  describe "creating a script" do
    test "successful", %{product: product, user: user} do
      {:ok, script} =
        Scripts.create(product, user, %{
          name: "MOTD",
          text: "NervesMOTD.print()"
        })

      assert script.product_id == product.id
      assert script.created_by_id == user.id
    end
  end

  describe "updating a script" do
    test "successful update", %{product: product, user: user} do
      {:ok, script} =
        Scripts.create(product, user, %{
          name: "MOTD",
          text: "NervesMOTD.print()"
        })

      {:ok, script} =
        Scripts.update(script, user, %{name: "New Name"})

      assert script.name == "New Name"
      assert script.last_updated_by_id == user.id
    end
  end
end

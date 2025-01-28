defmodule NervesHub.ScriptsTest do
  alias NervesHub.Accounts
  use NervesHub.DataCase

  alias NervesHub.Fixtures
  alias NervesHub.Scripts

  setup do
    user = Fixtures.user_fixture()
    user2 = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)

    %{user: user, user2: user2, org: org, product: product}
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

    test "other user updates script", %{
      product: product,
      user: user,
      user2: user2
    } do
      {:ok, script} =
        Scripts.create(product, user, %{
          name: "MOTD",
          text: "NervesMOTD.print()"
        })

      {:ok, script} =
        Scripts.update(script, user, %{name: "New Name"})

      {:ok, script} =
        Scripts.update(script, user2, %{text: "New text"})

      assert script.text == "New text"
      assert script.last_updated_by_id == user2.id
    end
  end

  describe "user removal" do
    test "user is removed - editor fields are nilified", %{product: product, user: user} do
      {:ok, script} =
        Scripts.create(product, user, %{
          name: "MOTD",
          text: "NervesMOTD.print()"
        })

      {:ok, _script} =
        Scripts.update(script, user, %{name: "New Name"})

      Accounts.remove_account(user.id)

      script = Scripts.get!(script.id)
      assert script.created_by_id == nil
      assert script.last_updated_by_id == nil
    end
  end
end

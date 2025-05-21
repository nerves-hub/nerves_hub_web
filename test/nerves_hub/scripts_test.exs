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
    test "create script without tags", %{product: product, user: user} do
      {:ok, script} =
        Scripts.create(product, user, %{
          name: "MOTD",
          text: "NervesMOTD.print()"
        })

      assert script.product_id == product.id
      assert script.created_by_id == user.id
    end

    test "create script with tags", %{product: product, user: user} do
      {:ok, script} =
        Scripts.create(product, user, %{
          name: "MOTD",
          text: "NervesMOTD.print()",
          tags: "red, green"
        })

      assert script.product_id == product.id
      assert script.created_by_id == user.id
      assert script.tags == ["red", "green"]
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
        Scripts.update(script, user, %{name: "New Name", tags: "foo,bar"})

      assert script.name == "New Name"
      assert script.tags == ["foo", "bar"]
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
    test "user is removed - editor fields are nullified", %{product: product, user: user} do
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

  describe "filter" do
    test "filter on tags", %{product: product, user: user} do
      {:ok, with_tags} =
        Scripts.create(product, user, %{
          name: "MOTD",
          text: "NervesMOTD.print()",
          tags: "red, green"
        })

      {:ok, _without_tags} =
        Scripts.create(product, user, %{
          name: "Another script",
          text: "Some code"
        })

      scripts = Scripts.get_by_product_and_tags(product, "red")
      assert length(scripts) == 1

      [script] = scripts
      assert script.name == with_tags.name
      assert script.tags == with_tags.tags
    end
  end
end

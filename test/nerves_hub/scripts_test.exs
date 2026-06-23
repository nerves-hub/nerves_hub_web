defmodule NervesHub.ScriptsTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Accounts
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
      {:ok, script1} =
        Scripts.create(product, user, %{
          name: "MOTD",
          text: "NervesMOTD.print()",
          tags: "hello, world"
        })

      {:ok, _script} =
        Scripts.create(product, user, %{
          name: "Another script",
          text: "Some code",
          tags: "world"
        })

      {scripts, _page} = Scripts.filter(product, %{filters: %{tags: "hello"}})
      [script] = scripts

      assert script.name == script1.name
      assert script.tags == script1.tags

      {scripts, _page} = Scripts.filter(product, %{filters: %{tags: "world"}})
      assert length(scripts) == 2

      {scripts, _page} = Scripts.filter(product, %{filters: %{tags: "world, hello"}})
      [script] = scripts

      assert script.name == script1.name
      assert script.tags == script1.tags
    end
  end

  describe "distinct_tags_for_product/1" do
    test "returns sorted, deduplicated tags across a product's scripts", %{product: product, user: user} do
      {:ok, _} = Scripts.create(product, user, %{name: "One", text: "x", tags: "info, reboot"})
      {:ok, _} = Scripts.create(product, user, %{name: "Two", text: "x", tags: "info, network"})
      {:ok, _} = Scripts.create(product, user, %{name: "Three", text: "x"})

      assert Scripts.distinct_tags_for_product(product) == ["info", "network", "reboot"]
    end

    test "is scoped to the given product", %{user: user, org: org} do
      product_a = Fixtures.product_fixture(user, org, %{name: "Product A"})
      product_b = Fixtures.product_fixture(user, org, %{name: "Product B"})

      {:ok, _} = Scripts.create(product_a, user, %{name: "A", text: "x", tags: "alpha"})
      {:ok, _} = Scripts.create(product_b, user, %{name: "B", text: "x", tags: "beta"})

      assert Scripts.distinct_tags_for_product(product_a) == ["alpha"]
      assert Scripts.distinct_tags_for_product(product_b) == ["beta"]
    end

    test "returns an empty list when no scripts have tags", %{product: product} do
      assert Scripts.distinct_tags_for_product(product) == []
    end
  end
end

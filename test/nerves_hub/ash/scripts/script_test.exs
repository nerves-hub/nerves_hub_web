defmodule NervesHub.Ash.Scripts.ScriptTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Ash.Scripts.Script
  alias NervesHub.Fixtures

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    script = Fixtures.support_script_fixture(product, user)

    %{user: user, product: product, script: script}
  end

  describe "read" do
    test "get by id", %{script: script} do
      found = Script.get!(script.id)
      assert found.id == script.id
      assert found.name == script.name
    end

    test "list_by_product returns scripts", %{product: product, script: script} do
      scripts = Script.list_by_product!(product.id)
      assert Enum.any?(scripts, &(&1.id == script.id))
    end

    test "get_by_product_and_name returns script", %{product: product, script: script} do
      found = Script.get_by_product_and_name!(product.id, script.name)
      assert found.id == script.id
    end

    test "get_by_product_and_id returns script", %{product: product, script: script} do
      found = Script.get_by_product_and_id!(product.id, script.id)
      assert found.id == script.id
    end
  end

  describe "create" do
    test "creates script with valid params", %{user: user, product: product} do
      script =
        Script.create!(%{
          name: "Test Script",
          text: "IO.puts('hello')",
          product_id: product.id,
          created_by_id: user.id,
          last_updated_by_id: user.id
        })

      assert script.id
      assert script.name == "Test Script"
      assert script.product_id == product.id
    end
  end

  describe "update" do
    test "updates script name and text", %{script: script, user: user} do
      ash_script = Script.get!(script.id)

      updated =
        Script.update!(ash_script, %{
          name: "Updated Script",
          text: "new code",
          last_updated_by_id: user.id
        })

      assert updated.name == "Updated Script"
      assert updated.text == "new code"
    end
  end

  describe "count_by_product" do
    test "returns script count for product", %{product: product} do
      count = Script.count_by_product!(product.id)
      assert is_integer(count)
      assert count >= 1
    end
  end

  describe "destroy" do
    test "deletes script", %{script: script} do
      ash_script = Script.get!(script.id)
      :ok = Script.destroy!(ash_script)
    end
  end
end

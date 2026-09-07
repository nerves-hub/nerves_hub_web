defmodule NervesHub.Scripts.ScriptFilteringTest do
  use NervesHub.DataCase, async: true

  import Ecto.Query

  alias NervesHub.Scripts.Script
  alias NervesHub.Scripts.ScriptFiltering

  # We test through the actual DB query layer to verify the SQL fragments work.
  # ScriptFiltering builds Ecto query fragments, so query tests are the right level.

  setup do
    user = NervesHub.Fixtures.user_fixture()
    org = NervesHub.Fixtures.org_fixture(user)
    product = NervesHub.Fixtures.product_fixture(user, org)

    {:ok, script_a} =
      NervesHub.Scripts.create(product, user, %{
        name: "deploy_all",
        text: "echo hi",
        tags: ["production", "alpha"]
      })

    {:ok, script_b} =
      NervesHub.Scripts.create(product, user, %{
        name: "restart_web",
        text: "echo bye",
        tags: ["staging"]
      })

    {:ok, script_c} =
      NervesHub.Scripts.create(product, user, %{
        name: "check_health",
        text: "echo ok",
        tags: []
      })

    {:ok, product: product, script_a: script_a, script_b: script_b, script_c: script_c}
  end

  defp query_scripts(product, filters) do
    base = from(s in Script, where: s.product_id == ^product.id)

    base
    |> ScriptFiltering.build_filters(filters)
    |> NervesHub.Repo.all()
  end

  describe "build_filters/2 - name filter" do
    test "filters by name with ILIKE", %{product: product, script_a: script_a} do
      results = query_scripts(product, %{name: "deploy"})
      assert Enum.any?(results, &(&1.id == script_a.id))
    end

    test "returns nothing for non-matching name", %{product: product} do
      results = query_scripts(product, %{name: "zzz_no_match"})
      assert results == []
    end

    test "empty string name filter returns all", %{product: product} do
      results = query_scripts(product, %{name: ""})
      assert length(results) == 3
    end
  end

  describe "build_filters/2 - tags filter" do
    test "filters scripts that have the given tag", %{product: product, script_a: script_a} do
      results = query_scripts(product, %{tags: ["production"]})
      ids = Enum.map(results, & &1.id)
      assert script_a.id in ids
    end

    test "empty string tags returns all", %{product: product} do
      results = query_scripts(product, %{tags: ""})
      assert length(results) == 3
    end
  end

  describe "build_filters/2 - search filter" do
    test "matches name with search term", %{product: product, script_a: script_a} do
      results = query_scripts(product, %{search: "deploy"})
      assert Enum.any?(results, &(&1.id == script_a.id))
    end

    test "matches tags with search term", %{product: product, script_a: script_a} do
      results = query_scripts(product, %{search: "alpha"})
      assert Enum.any?(results, &(&1.id == script_a.id))
    end

    test "empty string search returns all", %{product: product} do
      results = query_scripts(product, %{search: ""})
      assert length(results) == 3
    end
  end

  describe "build_filters/2 - unknown key" do
    test "ignores unknown filter keys and returns all", %{product: product} do
      results = query_scripts(product, %{totally_unknown: "val"})
      assert length(results) == 3
    end
  end

  describe "sort/2" do
    test "sorts by name ascending", %{product: product} do
      base = from(s in Script, where: s.product_id == ^product.id)

      results =
        base
        |> ScriptFiltering.sort({:asc, :name})
        |> NervesHub.Repo.all()

      names = Enum.map(results, & &1.name)
      assert names == Enum.sort(names)
    end

    test "sorts by name descending", %{product: product} do
      base = from(s in Script, where: s.product_id == ^product.id)

      results =
        base
        |> ScriptFiltering.sort({:desc, :name})
        |> NervesHub.Repo.all()

      names = Enum.map(results, & &1.name)
      assert names == Enum.sort(names, &>=/2)
    end
  end
end

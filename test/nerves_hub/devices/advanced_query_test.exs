defmodule NervesHub.Devices.AdvancedQueryTest do
  use NervesHub.DataCase, async: true

  import Ecto.Query

  alias NervesHub.AdvancedQueryFixtures
  alias NervesHub.Devices
  alias NervesHub.Devices.AdvancedQuery
  alias NervesHub.Devices.Device
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  setup {AdvancedQueryFixtures, :setup_devices}

  describe "references_column?/3" do
    test "detects a referenced column anywhere in the expression", %{product: product} do
      assert AdvancedQuery.references_column?(~s|deleted = "true"|, product.id, "deleted")

      assert AdvancedQuery.references_column?(
               ~s|health_status = "healthy" or deleted = "false"|,
               product.id,
               "deleted"
             )

      assert AdvancedQuery.references_column?(~s|not deleted = "true"|, product.id, "deleted")
    end

    test "detects metric columns and columns inside multi-comparison queries", %{product: product} do
      assert AdvancedQuery.references_column?(~s|metric:cpu_temp > 5|, product.id, "metric:cpu_temp")

      assert AdvancedQuery.references_column?(
               ~s|tags contains "prod" and deleted = "false"|,
               product.id,
               "tags"
             )
    end

    test "is false when the column isn't referenced", %{product: product} do
      refute AdvancedQuery.references_column?(~s|tags contains "prod"|, product.id, "deleted")
    end

    test "is false for blank or invalid queries", %{product: product} do
      refute AdvancedQuery.references_column?(nil, product.id, "deleted")
      refute AdvancedQuery.references_column?("", product.id, "deleted")
      refute AdvancedQuery.references_column?("not a valid query !!!", product.id, "deleted")
    end
  end

  describe "apply_to_query/3" do
    # Uses a base query with only the default `d` binding, plus the `identifier`
    # column (which needs no joins), to test the function's contract directly.
    defp applied_identifiers(product, raw) do
      Device
      |> where([d], d.product_id == ^product.id)
      |> AdvancedQuery.apply_to_query(raw, product.id)
      |> select([d], d.identifier)
      |> Repo.all()
      |> Enum.sort()
    end

    test "leaves the query unchanged for nil, empty, and invalid input", %{product: product} do
      all = ["connected", "never_connected", "tagged", "untagged"]

      assert applied_identifiers(product, nil) == all
      assert applied_identifiers(product, "") == all
      assert applied_identifiers(product, "garbage !!!") == all
      # valid syntax but an invalid value is dropped too
      assert applied_identifiers(product, ~s|platform = "does-not-exist"|) == all
    end

    test "applies a valid query", %{product: product} do
      assert applied_identifiers(product, ~s|identifier like "tagged"|) == ["tagged"]
    end
  end

  describe "Devices.filter/3 integration - binding coverage" do
    # These run through the real `Devices.filter` pipeline (and therefore the
    # real `common_filter_query` bindings), so a rename of a named binding that
    # the compiler relies on would be caught here - the isolated compiler tests
    # supply their own bindings and would not notice.

    test "health_status uses the latest_health binding", %{product: product, user: user} do
      assert via_filter(product, user, ~s|health_status = "healthy"|) == ["tagged"]
    end

    test "connection uses the latest_connection binding", %{product: product, user: user} do
      assert via_filter(product, user, ~s|connection = "connected"|) == ["connected"]
    end

    test "update_status uses the inflight_update binding", %{
      product: product,
      user: user,
      firmware: firmware,
      tagged: tagged
    } do
      {:ok, _} = Fixtures.inflight_update(tagged, firmware)

      assert via_filter(product, user, ~s|update_status is "updating"|) == ["tagged"]
    end

    test "metric runs the correlated subquery", %{product: product, user: user, tagged: tagged} do
      AdvancedQueryFixtures.save_metric(tagged, "cpu_temp", 99.0, 10)

      assert via_filter(product, user, ~s|metric:cpu_temp > 50|) == ["tagged"]
    end

    test "an invalid advanced query is ignored (returns the full unfiltered list)", %{product: product, user: user} do
      assert via_filter(product, user, "totally not valid !!!") ==
               ["connected", "never_connected", "tagged", "untagged"]
    end
  end

  describe "Devices.filter/3 integration - deleted override" do
    setup %{tagged: tagged} do
      # Soft-delete "tagged" (which carries the "prod" tag) so we can show that a
      # query which doesn't reference `deleted` still hides it.
      {1, _} =
        Repo.update_all(where(Device, id: ^tagged.id),
          set: [deleted_at: DateTime.truncate(DateTime.utc_now(), :second)]
        )

      :ok
    end

    test "soft-deleted devices are excluded by default", %{product: product, user: user} do
      assert via_filter(product, user, "") == ["connected", "never_connected", "untagged"]
    end

    test ~s|`deleted = "true"` overrides the default exclusion|, %{product: product, user: user} do
      assert via_filter(product, user, ~s|deleted = "true"|) == ["tagged"]
    end

    test ~s|`deleted = "false"` shows only live devices|, %{product: product, user: user} do
      assert via_filter(product, user, ~s|deleted = "false"|) == ["connected", "never_connected", "untagged"]
    end

    test "a query that doesn't reference deleted still excludes soft-deleted devices", %{
      product: product,
      user: user
    } do
      # "tagged" is the only device with the "prod" tag, but it's soft-deleted,
      # so a non-deleted-referencing query still hides it.
      assert via_filter(product, user, ~s|tags contains "prod"|) == []
    end
  end

  defp via_filter(product, user, advanced_query) do
    opts = %{
      sort: {:asc, :identifier},
      filters: %{display_deleted: "exclude", advanced_query: advanced_query}
    }

    {devices, _meta} = Devices.filter(product, user, opts)
    devices |> Enum.map(& &1.identifier) |> Enum.sort()
  end
end

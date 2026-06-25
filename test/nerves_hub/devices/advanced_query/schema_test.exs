defmodule NervesHub.Devices.AdvancedQuery.SchemaTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.AdvancedQueryFixtures
  alias NervesHub.Devices.AdvancedQuery.Schema

  # No product needed: these only exercise the static whitelist.
  describe "column?/1" do
    test "is true for fixed columns and false for unknown ones" do
      assert Schema.column?("platform")
      assert Schema.column?("tags")
      assert Schema.column?("deployment_group")
      refute Schema.column?("bogus")
      refute Schema.column?("")
    end

    test "accepts any non-empty metric:<key> leniently" do
      assert Schema.column?("metric:cpu_temp")
      assert Schema.column?("metric:some_custom_key")
      refute Schema.column?("metric:")
    end
  end

  describe "operators/1 and operator?/2" do
    test "returns the operators for known columns" do
      assert Schema.operators("platform") == ["=", "!="]
      assert Schema.operators("tags") == ["contains", "not_contains"]
      assert Schema.operators("update_status") == ["is", "is not"]
      assert Schema.operators("identifier") == ["like", "not like"]
    end

    test "returns numeric operators for metric columns" do
      assert Schema.operators("metric:cpu_temp") == [">", ">=", "<", "<="]
    end

    test "returns :error for an unknown column" do
      assert Schema.operators("bogus") == :error
    end

    test "validates operator/column pairs" do
      assert Schema.operator?("platform", "=")
      refute Schema.operator?("platform", "contains")
      assert Schema.operator?("metric:cpu_temp", ">=")
      refute Schema.operator?("bogus", "=")
    end
  end

  describe "value?/3 for columns that don't need product data" do
    test "metric columns accept any number" do
      assert Schema.value?("metric:cpu_temp", "10", 1)
      assert Schema.value?("metric:cpu_temp", "1.5", 1)
      assert Schema.value?("metric:cpu_temp", "-3", 1)
      refute Schema.value?("metric:cpu_temp", "abc", 1)
      refute Schema.value?("metric:cpu_temp", "10abc", 1)
    end

    test "freeform text columns accept any non-empty value" do
      assert Schema.value?("identifier", "anything", 1)
      assert Schema.value?("identifier", "%wild_card%", 1)
      refute Schema.value?("identifier", "", 1)
    end
  end

  describe "sentinels and prefixes" do
    test "exposes the shared not-set sentinel and metric prefix" do
      assert Schema.not_set_value() == ":not_set"
      assert Schema.metric_prefix() == "metric:"
    end
  end

  describe "value?/3 against product data" do
    setup {AdvancedQueryFixtures, :setup_devices}

    test "validates enum-style columns against the product's values", %{product: product, platform: platform} do
      assert Schema.value?("platform", platform, product.id)
      refute Schema.value?("platform", "does-not-exist", product.id)
    end

    test "validates firmware against the product's firmware uuids", %{product: product, firmware: firmware} do
      assert Schema.value?("firmware", firmware.uuid, product.id)
      refute Schema.value?("firmware", "00000000-0000-0000-0000-000000000000", product.id)
    end

    test "the not-set sentinel is valid for nullable columns", %{product: product} do
      assert Schema.value?("tags", ":not_set", product.id)
      assert Schema.value?("deployment_group", ":not_set", product.id)
      assert Schema.not_set_value() in Schema.values("tags", product.id)
      assert Schema.not_set_value() in Schema.values("deployment_group", product.id)
    end
  end
end

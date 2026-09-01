defmodule NervesHub.Devices.AdvancedQuery.SidebarSyncTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Devices.AdvancedQuery.SidebarSync
  alias NervesHub.Fixtures

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
    device = Fixtures.device_fixture(org, product, firmware, %{tags: ["prod"]})

    {:ok, %{product: product, device: device}}
  end

  defp form(overrides) do
    Map.merge(
      %{
        "identifier" => "",
        "health_status" => "",
        "connection" => "",
        "connection_type" => "",
        "updates" => "",
        "platform" => "",
        "alarm_status" => "",
        "alarm" => "",
        "has_no_tags" => "false",
        "only_updating" => "false",
        "metrics_key" => "",
        "metrics_operator" => "gt",
        "metrics_value" => ""
      },
      overrides
    )
  end

  describe "merge/3" do
    test "encodes sidebar selections into an empty query", %{product: product} do
      params = form(%{"connection" => "connected", "health_status" => "unhealthy"})

      assert {:ok, query, reset} = SidebarSync.merge(params, "", product.id)
      assert query == ~s|health_status = "unhealthy" and connection = "connected"|
      assert reset["connection"] == ""
      assert reset["health_status"] == ""
    end

    test "maps the not-seen options onto last_seen", %{product: product} do
      params = form(%{"connection" => "not_seen_in_seven_days"})

      assert {:ok, ~s|last_seen < "7 days ago"|, _reset} = SidebarSync.merge(params, "", product.id)
    end

    test "replaces a control's previous comparison instead of stacking", %{product: product} do
      params = form(%{"connection" => "disconnected"})

      assert {:ok, query, _reset} = SidebarSync.merge(params, ~s|connection = "connected"|, product.id)
      assert query == ~s|connection = "disconnected"|
    end

    test "leaves comparisons the sidebar cannot express untouched", %{product: product} do
      existing = ~s|tags contains "prod" and metric:cpu_temp >= 5|
      params = form(%{"connection" => "connected"})

      assert {:ok, query, _reset} = SidebarSync.merge(params, existing, product.id)
      assert query == ~s|tags contains "prod" and metric:cpu_temp >= 5 and connection = "connected"|
    end

    test "leaves compound expressions untouched and parenthesized", %{product: product} do
      existing = ~s|(connection = "connected" or health_status = "unhealthy")|
      params = form(%{"updates" => "disabled"})

      assert {:ok, query, _reset} = SidebarSync.merge(params, existing, product.id)
      assert query == ~s|(connection = "connected" or health_status = "unhealthy") and updates = "disabled"|
    end

    test "does not claim ambiguous duplicated comparisons", %{product: product} do
      existing = ~s|metric:cpu_temp > 5 and metric:load_1min > 2|
      params = form(%{"connection" => "connected"})

      assert {:ok, query, _reset} = SidebarSync.merge(params, existing, product.id)
      assert query == ~s|metric:cpu_temp > 5 and metric:load_1min > 2 and connection = "connected"|
    end

    test "encodes the metrics trio and untagged and updating controls", %{product: product} do
      params =
        form(%{
          "metrics_key" => "cpu_temp",
          "metrics_operator" => "lt",
          "metrics_value" => "40",
          "has_no_tags" => "true",
          "only_updating" => "true"
        })

      assert {:ok, query, reset} = SidebarSync.merge(params, "", product.id)
      assert query == ~s|tags contains ":not_set" and update_status is "updating" and metric:cpu_temp < 40|
      assert reset["metrics_key"] == ""
      assert reset["metrics_operator"] == "gt"
      assert reset["has_no_tags"] == "false"
    end

    test "keeps a half-filled metrics trio in the params", %{product: product} do
      params = form(%{"metrics_key" => "cpu_temp", "metrics_operator" => "lt"})

      assert {:ok, "", reset} = SidebarSync.merge(params, "", product.id)
      assert reset["metrics_key"] == "cpu_temp"
      assert reset["metrics_operator"] == "lt"
    end

    test "returns :error for a query that does not parse", %{product: product} do
      assert :error = SidebarSync.merge(form(%{}), ~s|connection = |, product.id)
    end
  end

  describe "derive/2" do
    test "reads control state back from the query", %{product: product} do
      query = ~s|connection = "connected" and metric:cpu_temp > 40 and update_status is "updating"|

      assert SidebarSync.derive(query, product.id) == %{
               connection: "connected",
               metrics_key: "cpu_temp",
               metrics_operator: "gt",
               metrics_value: "40",
               only_updating: true
             }
    end

    test "maps last_seen back onto the connection control", %{product: product} do
      assert SidebarSync.derive(~s|last_seen < "14 days ago"|, product.id) == %{
               connection: "not_seen_in_fourteen_days"
             }
    end

    test "strips the wildcards from an identifier pattern", %{product: product} do
      assert SidebarSync.derive(~s|identifier like "%abc%"|, product.id) == %{identifier: "abc"}
    end

    test "claims nothing from compound or ambiguous expressions", %{product: product} do
      assert SidebarSync.derive(~s|(connection = "connected" or health_status = "unhealthy")|, product.id) == %{}

      assert SidebarSync.derive(~s|metric:cpu_temp > 5 and metric:load_1min > 2|, product.id) == %{}
    end

    test "round trips through merge", %{product: product} do
      params = form(%{"connection" => "disconnected", "alarm_status" => "with", "identifier" => "abc"})

      {:ok, query, _reset} = SidebarSync.merge(params, "", product.id)
      derived = SidebarSync.derive(query, product.id)

      assert derived == %{connection: "disconnected", alarm_status: "with", identifier: "abc"}

      derived_params = Map.new(derived, fn {key, value} -> {to_string(key), to_string(value)} end)
      {:ok, query2, _reset} = SidebarSync.merge(form(derived_params), query, product.id)
      assert query2 == query
    end
  end
end

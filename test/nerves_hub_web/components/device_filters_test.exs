defmodule NervesHubWeb.Components.DeviceFiltersTest do
  use ExUnit.Case, async: true

  alias NervesHub.Devices.DeviceFiltering
  alias NervesHubWeb.Components.DeviceFilters

  defp filters(changes), do: Map.merge(DeviceFiltering.default_filters(), Map.new(changes))

  describe "applied/1" do
    test "lists the filters off their defaults, leaving out the tab and the query" do
      assert DeviceFilters.applied(DeviceFiltering.default_filters()) == []

      assert DeviceFilters.applied(
               filters(state: "online", reason: "unhealthy", advanced_query: "tags = beta", metrics_operator: "lt")
             ) == []

      assert DeviceFilters.applied(filters(platform: "rpi4", health_status: "unhealthy", is_pinned: true)) ==
               [:health_status, :platform, :is_pinned]
    end
  end

  describe "join_choices/1" do
    test "joins each list of choices, dropping the empty one a form sends for none" do
      assert DeviceFilters.join_choices(%{
               "health_status" => ["", "warning", "unhealthy"],
               "connection" => [""],
               "platform" => "rpi4"
             }) == %{"health_status" => "warning,unhealthy", "connection" => "", "platform" => "rpi4"}
    end
  end

  describe "facets/3" do
    test "counts every listed choice, and any chosen that isn't listed" do
      facets = DeviceFilters.facets(filters(updates: "enabled,updating"), ["2.4.0"], ["SomeAlarm"])

      assert facets.health_status == ~w(healthy warning unhealthy unknown)
      assert facets.firmware_version == ["2.4.0", "Unknown"]
      assert facets.alarm == ["SomeAlarm"]
      assert facets.updates == ~w(updating failed-updates penalty-box disabled enabled)
    end
  end

  describe "token_text/4" do
    test "names the filter and its choices, in the panel's order" do
      assert DeviceFilters.token_text(:health_status, filters(health_status: "unhealthy,warning"), [], []) ==
               "health: warning, unhealthy"

      assert DeviceFilters.token_text(:connection, filters(connection: "not_seen_in_seven_days"), [], []) ==
               "connection: not seen 7 d+"

      assert DeviceFilters.token_text(:firmware_version, filters(firmware_version: "2.2.0,Unknown"), [], []) ==
               "firmware: 2.2.0, Unknown"
    end

    test "names the deployment group rather than its id" do
      groups = [%{id: 7, name: "Field units"}]

      assert DeviceFilters.token_text(:deployment_id, filters(deployment_id: "7"), groups, []) ==
               "group: Field units"

      assert DeviceFilters.token_text(:deployment_id, filters(deployment_id: "-1"), groups, []) == "group: none"
    end

    test "writes a metric as its comparison once it has a value" do
      assert DeviceFilters.token_text(:metrics_key, filters(metrics_key: "cpu_temp"), [], []) == "metric: cpu_temp"

      assert DeviceFilters.token_text(
               :metrics_key,
               filters(metrics_key: "cpu_temp", metrics_operator: "lt", metrics_value: "40"),
               [],
               []
             ) == "cpu_temp < 40"
    end
  end
end

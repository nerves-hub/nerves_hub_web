defmodule NervesHubWeb.Components.UtilsTest do
  use ExUnit.Case

  alias NervesHubWeb.Components.Utils

  describe "format_serial/1" do
    test "serial number is formatted in hex" do
      assert Utils.format_serial("112346101875805641052401911002393715100") ==
               "54:85:12:79:FB:15:C2:FC:26:B2:50:35:4C:EF:A1:9C"
    end
  end

  describe "role_options/0" do
    test "a list of formatted tuples is returned" do
      assert Utils.role_options() == [
               {"Admin", :admin},
               {"Manage", :manage},
               {"View", :view}
             ]
    end
  end

  describe "cpu_temp_to_status/1" do
    test "temp < 60 returns empty string" do
      assert Utils.cpu_temp_to_status(59) == ""
    end

    test "temp between 60 and 89 returns 'warn'" do
      assert Utils.cpu_temp_to_status(60) == "warn"
      assert Utils.cpu_temp_to_status(89) == "warn"
    end

    test "temp >= 90 returns 'danger'" do
      assert Utils.cpu_temp_to_status(90) == "danger"
      assert Utils.cpu_temp_to_status(100) == "danger"
    end
  end

  describe "usage_percent_to_status/1" do
    test "usage < 80 returns empty string" do
      assert Utils.usage_percent_to_status(79) == ""
    end

    test "usage between 80 and 89 returns 'warn'" do
      assert Utils.usage_percent_to_status(80) == "warn"
      assert Utils.usage_percent_to_status(89) == "warn"
    end

    test "usage >= 90 returns 'danger'" do
      assert Utils.usage_percent_to_status(90) == "danger"
      assert Utils.usage_percent_to_status(100) == "danger"
    end
  end

  describe "tags_to_string/1" do
    test "with a list of tags returns comma-separated string" do
      assert Utils.tags_to_string(["alpha", "beta", "gamma"]) == "alpha, beta, gamma"
    end

    test "with a map containing :tags key delegates to the list" do
      assert Utils.tags_to_string(%{tags: ["foo", "bar"]}) == "foo, bar"
    end
  end

  describe "disk_usage/1" do
    test "with valid disk metrics map returns a formatted string" do
      metrics = %{
        "disk_available_kb" => 8_000_000,
        "disk_total_kb" => 10_000_000,
        "disk_used_percentage" => 20
      }

      result = Utils.disk_usage(metrics)

      assert is_binary(result)
      assert String.contains?(result, "(20%)")
    end
  end
end

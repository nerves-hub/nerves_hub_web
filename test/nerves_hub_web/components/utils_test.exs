defmodule NervesHubWeb.Components.UtilsTest do
  use ExUnit.Case

  alias NervesHub.Accounts.OrgRole
  alias NervesHub.Accounts.OrgUser
  alias NervesHubWeb.Components.Utils

  describe "format_serial/1 with integer" do
    test "integer serial number is formatted in hex" do
      n = 112_346_101_875_805_641_052_401_911_002_393_715_100
      assert Utils.format_serial(n) == "54:85:12:79:FB:15:C2:FC:26:B2:50:35:4C:EF:A1:9C"
    end
  end

  describe "tags_to_string/1 with non-list" do
    test "returns the value unchanged when it's not a list or map" do
      assert Utils.tags_to_string("already a string") == "already a string"
      assert Utils.tags_to_string(nil) == nil
    end
  end

  describe "format_serial/1" do
    test "serial number is formatted in hex" do
      assert Utils.format_serial("112346101875805641052401911002393715100") ==
               "54:85:12:79:FB:15:C2:FC:26:B2:50:35:4C:EF:A1:9C"
    end
  end

  describe "role_options/1" do
    test "the built-in roles, when the org has no roles of its own" do
      assert Utils.role_options() == [
               {"Admin", "admin"},
               {"Manage", "manage"},
               {"View", "view"}
             ]
    end

    test "the built-in roles and the org's own, grouped" do
      assert Utils.role_options([%OrgRole{id: 7, name: "Release Manager"}]) == [
               {"Built-in roles", [{"Admin", "admin"}, {"Manage", "manage"}, {"View", "view"}]},
               {"Custom roles", [{"Release Manager", "custom:7"}]}
             ]
    end
  end

  describe "role_choice/1" do
    test "picks the role a member holds" do
      assert Utils.role_choice(%OrgUser{role: :manage}) == "manage"
      assert Utils.role_choice(%OrgUser{org_role_id: 7, org_role: %OrgRole{id: 7}}) == "custom:7"
    end

    test "falls back to view rather than the first option, admin" do
      assert Utils.role_choice(%OrgUser{role: nil}) == "view"
      assert Utils.role_choice(%OrgUser{org_role_id: 7, org_role: nil}) == "view"
    end
  end

  describe "role_name/1" do
    test "names built-in and custom roles, and the role a member holds" do
      assert Utils.role_name(:manage) == "Manage"
      assert Utils.role_name(%OrgRole{name: "Release Manager"}) == "Release Manager"
      assert Utils.role_name(%OrgUser{role: :view}) == "View"
      assert Utils.role_name(%OrgUser{org_role_id: 7, org_role: %OrgRole{name: "Release Manager"}}) == "Release Manager"
      assert Utils.role_name(%OrgUser{org_role_id: 7, org_role: nil}) == "No role"
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

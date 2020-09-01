defmodule NervesHubWWWWeb.LayoutViewTest do
  use ExUnit.Case
  use NervesHubWWWWeb.ConnCase, async: true

  import NervesHubWWWWeb.LayoutView,
    only: [humanize_size: 1, humanize_seconds: 1, org_device_limit: 1]

  alias NervesHubWebCore.Accounts.OrgLimit
  alias NervesHubWebCore.Fixtures

  describe "Test humanize functions" do
    test "humanize size" do
      result = humanize_size(1_167_772_160)
      assert result == "1.088 GiB"
      result = humanize_size(167_772_160)
      assert result == "160.0 MiB"
      result = humanize_size(772_160)
      assert result == "754.063 KiB"
    end

    test "humanize seconds" do
      result = humanize_seconds(3456)
      assert result == "57 minutes, 36 seconds"
      result = humanize_seconds(60 * 60 * 24 * 7)
      assert result == "1 week"
    end
  end

  describe "org_device_limit/1" do
    test "a string representation of total devices and device limit is returned", %{conn: conn} do
      %{org: org, device: _} = Fixtures.standard_fixture()
      limits = %OrgLimit{devices: 3}

      conn = Map.put(conn, :assigns, %{org: org, current_limit: limits})

      org_device_limit(conn)
      assert org_device_limit(conn) == "1/3"
    end
  end
end

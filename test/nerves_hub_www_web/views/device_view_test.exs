defmodule NervesHubWWWWeb.DeviceViewTest do
  use NervesHubWWWWeb.ConnCase, async: true

  alias NervesHubWWWWeb.DeviceView

  describe "display_status/1" do
    test "nothing happens to regular strings" do
      assert DeviceView.display_status("test status") == "test status"
    end

    test "hyphenated strings are formatted" do
      assert DeviceView.display_status("test-status") == "test status"
    end

    test "nil is returned for other types" do
      assert DeviceView.display_status(nil) == nil
    end
  end
end

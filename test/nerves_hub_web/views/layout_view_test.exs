defmodule NervesHubWeb.LayoutViewTest do
  use ExUnit.Case
  use DefaultMocks
  use NervesHubWeb.ConnCase, async: true

  import NervesHubWeb.LayoutView,
    only: [humanize_size: 1, humanize_seconds: 1]

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
end

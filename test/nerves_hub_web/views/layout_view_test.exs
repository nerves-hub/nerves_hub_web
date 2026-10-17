defmodule NervesHubWeb.LayoutViewTest do
  use ExUnit.Case
  use DefaultMocks
  use NervesHubWeb.ConnCase, async: true

  import NervesHubWeb.LayoutView,
    only: [humanize_size: 1]

  describe "Test humanize functions" do
    test "humanize size" do
      result = humanize_size(1_167_772_160)
      assert result == "1.09 GB"
      result = humanize_size(167_772_160)
      assert result == "160.0 MB"
      result = humanize_size(772_160)
      assert result == "754.06 KB"
    end
  end
end

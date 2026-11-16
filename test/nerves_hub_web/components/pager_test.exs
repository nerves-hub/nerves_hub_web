defmodule NervesHubWeb.Components.PagerTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias NervesHubWeb.Components.Pager

  defp footer(pager) do
    pager = Map.merge(%{current_page: 1, total_pages: 1, page_size: 25, total_count: 3}, pager)
    render_component(&Pager.footer/1, %{id: "test-pager", pager: pager})
  end

  describe "footer/1" do
    test "shows a single page, with previous and next disabled" do
      html = footer(%{})

      assert html =~ ~s(id="test-pager-page-size")
      assert html =~ ~s(aria-current="page")
      assert html =~ ~r/aria-label="Previous page"\s+disabled/
      assert html =~ ~r/aria-label="Next page"\s+disabled/
    end

    test "is left out when there is nothing to page through" do
      refute footer(%{total_count: 0, total_pages: 0}) =~ "Pages"
    end

    test "says which page this is, for a phone" do
      html = footer(%{current_page: 2, total_pages: 4, total_count: 90})

      assert html =~ ~r/Page 2<\/span>\s+of 4 · 25 per page/
    end
  end
end

defmodule NervesHubWeb.API.PaginationHelpersTest do
  use ExUnit.Case, async: true

  alias NervesHubWeb.API.PaginationHelpers

  describe "atomize_pagination_params/1" do
    test "converts string page and page_size to integers" do
      assert PaginationHelpers.atomize_pagination_params(%{"page" => "3", "page_size" => "50"}) ==
               %{page: 3, page_size: 50}
    end

    test "passes through integer page and page_size unchanged" do
      assert PaginationHelpers.atomize_pagination_params(%{"page" => 2, "page_size" => 10}) ==
               %{page: 2, page_size: 10}
    end

    test "drops unknown keys" do
      assert PaginationHelpers.atomize_pagination_params(%{"page" => "1", "unknown" => "value"}) ==
               %{page: 1}
    end

    test "returns empty map for nil input" do
      assert PaginationHelpers.atomize_pagination_params(nil) == %{}
    end

    test "returns empty map for empty map input" do
      assert PaginationHelpers.atomize_pagination_params(%{}) == %{}
    end
  end

  describe "format_pagination_meta/1" do
    test "maps Flop.Meta fields to the expected output shape" do
      meta = %Flop.Meta{current_page: 2, page_size: 10, total_count: 45, total_pages: 5}

      assert PaginationHelpers.format_pagination_meta(meta) == %{
               page_number: 2,
               page_size: 10,
               total_entries: 45,
               total_pages: 5
             }
    end

    test "handles nil total_count" do
      meta = %Flop.Meta{current_page: 1, page_size: 25, total_count: nil, total_pages: nil}

      result = PaginationHelpers.format_pagination_meta(meta)
      assert result.total_entries == nil
      assert result.total_pages == nil
      assert result.page_number == 1
      assert result.page_size == 25
    end
  end
end

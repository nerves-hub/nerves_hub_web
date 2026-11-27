defmodule NervesHubWeb.API.PaginationHelpersTest do
  use ExUnit.Case, async: true

  alias NervesHubWeb.API.PaginationHelpers

  doctest PaginationHelpers, import: true

  describe "cast_pagination_params/1" do
    test "converts string page and page_size to integers" do
      assert PaginationHelpers.cast_pagination_params(%{"page" => "3", "page_size" => "50"}) ==
               {:ok, %{page: 3, page_size: 50}}
    end

    test "passes through integer page and page_size unchanged" do
      assert PaginationHelpers.cast_pagination_params(%{"page" => 2, "page_size" => 10}) ==
               {:ok, %{page: 2, page_size: 10}}
    end

    test "drops unknown keys" do
      assert PaginationHelpers.cast_pagination_params(%{"page" => "1", "unknown" => "value"}) ==
               {:ok, %{page: 1}}
    end

    test "returns an empty map for nil, an empty map, or empty values" do
      assert PaginationHelpers.cast_pagination_params(nil) == {:ok, %{}}
      assert PaginationHelpers.cast_pagination_params(%{}) == {:ok, %{}}
      assert PaginationHelpers.cast_pagination_params(%{"page" => "", "page_size" => ""}) == {:ok, %{}}
    end

    test "lowers a page size over the maximum to the maximum" do
      max = PaginationHelpers.max_page_size()

      assert max == 100
      assert PaginationHelpers.cast_pagination_params(%{"page_size" => "#{max}"}) == {:ok, %{page_size: max}}
      assert PaginationHelpers.cast_pagination_params(%{"page_size" => "#{max + 1}"}) == {:ok, %{page_size: max}}
      assert PaginationHelpers.cast_pagination_params(%{"page_size" => 1_000_000}) == {:ok, %{page_size: max}}

      assert PaginationHelpers.cast_pagination_params(%{"page_size" => "99999999999999999999999"}) ==
               {:ok, %{page_size: max}}
    end

    test "accepts pages up to the maximum" do
      max = PaginationHelpers.max_page()

      assert PaginationHelpers.cast_pagination_params(%{"page" => "#{max}"}) == {:ok, %{page: max}}
      assert {:error, {:invalid_query_param, _}} = PaginationHelpers.cast_pagination_params(%{"page" => "#{max + 1}"})
    end

    for value <- ["abc", "1.5", "10abc", " 5", "0", "-1", 0, -3, 2.0, ["1"], %{"a" => "1"}] do
      test "refuses page_size #{inspect(value)}" do
        assert {:error, {:invalid_query_param, message}} =
                 PaginationHelpers.cast_pagination_params(%{"page_size" => unquote(Macro.escape(value))})

        assert message ==
                 "pagination[page_size] must be a whole number of 1 or more, got #{inspect(unquote(Macro.escape(value)))}."
      end

      test "refuses page #{inspect(value)}" do
        assert {:error, {:invalid_query_param, message}} =
                 PaginationHelpers.cast_pagination_params(%{"page" => unquote(Macro.escape(value))})

        assert message ==
                 "pagination[page] must be a whole number from 1 to 2147483647, got #{inspect(unquote(Macro.escape(value)))}."
      end
    end

    test "refuses a pagination param that isn't a map" do
      assert {:error, {:invalid_query_param, message}} = PaginationHelpers.cast_pagination_params("50")
      assert message =~ ~s|pagination must be an object|
      assert message =~ ~s|got "50".|
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

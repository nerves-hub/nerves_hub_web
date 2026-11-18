defmodule NervesHub.ListQueryTest do
  use ExUnit.Case, async: true

  alias NervesHub.ListQuery

  doctest ListQuery

  describe "escape_like/1" do
    test "escapes ilike's wildcards and its escape character" do
      assert ListQuery.escape_like(~S"a%b_c\d") == ~S"a\%b\_c\\d"
    end

    test "leaves everything else alone" do
      assert ListQuery.escape_like("v1.2.3 (rc)") == "v1.2.3 (rc)"
    end
  end

  describe "positive_integer/2" do
    test "keeps a positive integer, or the text of one" do
      assert ListQuery.positive_integer(4, 1) == 4
      assert ListQuery.positive_integer("25", 10) == 25
    end

    test "falls back to the default for anything else" do
      for value <- [0, -2, "0", "-1", "2.5", "3abc", "", nil, 1.5] do
        assert ListQuery.positive_integer(value, 7) == 7
      end
    end
  end
end

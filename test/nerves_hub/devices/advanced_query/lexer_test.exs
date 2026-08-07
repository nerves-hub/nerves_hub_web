defmodule NervesHub.Devices.AdvancedQuery.LexerTest do
  use ExUnit.Case, async: true

  alias NervesHub.Devices.AdvancedQuery.Lexer
  alias NervesHub.Devices.AdvancedQuery.Lexer.Token

  describe "tokenize/1" do
    test "tokenizes a simple comparison" do
      assert {:ok, tokens} = Lexer.tokenize(~s|platform = "rpi4"|)

      assert tokens == [
               %Token{type: :ident, value: "platform", position: 0},
               %Token{type: :symbol, value: "=", position: 9},
               %Token{type: :string, value: "rpi4", position: 11},
               %Token{type: :eof, value: "", position: 17}
             ]
    end

    test "tokenizes parens, boolean keywords, and the != symbol" do
      assert {:ok, tokens} =
               Lexer.tokenize(~s|(platform = "rpi4" and tags contains "prod") or connection != "online"|)

      values = Enum.map(tokens, & &1.value)

      assert values == [
               "(",
               "platform",
               "=",
               "rpi4",
               "and",
               "tags",
               "contains",
               "prod",
               ")",
               "or",
               "connection",
               "!=",
               "online",
               ""
             ]
    end

    test "allows hyphens and underscores in identifiers and values" do
      assert {:ok, tokens} = Lexer.tokenize(~s|tags contains beta-boop|)
      assert Enum.map(tokens, & &1.value) == ["tags", "contains", "beta-boop", ""]
    end

    test "tokenizes a metric column (with colon) and comparison operators" do
      assert {:ok, tokens} = Lexer.tokenize(~s|metric:cpu_temp >= 10.5|)
      assert Enum.map(tokens, & &1.value) == ["metric:cpu_temp", ">=", "10.5", ""]
    end

    test "matches the longest comparison symbol first" do
      assert {:ok, tokens} = Lexer.tokenize("a>=b a>b a<=b a<b")
      symbols = tokens |> Enum.filter(&(&1.type == :symbol)) |> Enum.map(& &1.value)
      assert symbols == [">=", ">", "<=", "<"]
    end

    test "supports escaped quotes and backslashes inside strings" do
      assert {:ok, tokens} = Lexer.tokenize(~S|platform = "a \"quoted\" \\value"|)
      assert [_platform, _eq, string_token, _eof] = tokens
      assert string_token.value == ~S|a "quoted" \value|
    end

    test "skips surrounding and interleaved whitespace" do
      assert {:ok, tokens} = Lexer.tokenize("  platform   =\t\"rpi4\"\n")
      assert Enum.map(tokens, & &1.value) == ["platform", "=", "rpi4", ""]
    end

    test "returns an error with position for an unterminated string" do
      assert {:error, "unterminated string", 14} = Lexer.tokenize(~s|tags contains "unterminated|)
    end

    test "returns an error with position for an unexpected character" do
      assert {:error, _message, 9} = Lexer.tokenize(~s|platform @ "rpi4"|)
    end

    test "tokenizes an empty string to just eof" do
      assert {:ok, [%Token{type: :eof, value: "", position: 0}]} = Lexer.tokenize("")
    end
  end
end

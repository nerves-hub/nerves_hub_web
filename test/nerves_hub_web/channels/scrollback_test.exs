defmodule NervesHubWeb.Channels.ScrollbackTest do
  use ExUnit.Case, async: true

  alias NervesHubWeb.Channels.Scrollback

  defp append_all(scrollback, chunks), do: Enum.reduce(chunks, scrollback, &Scrollback.append(&2, &1))

  describe "append/2" do
    test "holds the line still being written and replays it with the rest" do
      scrollback = append_all(Scrollback.new(), ["one\ntw", "o\nthree"])

      assert Scrollback.text(scrollback) == "one\ntwo\nthree"
    end

    test "drops the oldest lines once the buffer is full" do
      scrollback = append_all(Scrollback.new(2), ["a\n", "b\n", "c\n"])

      assert Scrollback.text(scrollback) == "b\nc\n"
    end

    test "bounds output that never sends a newline" do
      # A `\r` progress bar or a loop of `IO.write/1` used to grow the held line
      # without limit, in a process that lives as long as the connection.
      scrollback = append_all(Scrollback.new(4), List.duplicate(String.duplicate("x", 500), 40))

      assert byte_size(Scrollback.text(scrollback)) < 20_000
    end

    test "banked pieces still reconstruct the original stream" do
      data = String.duplicate("y", 2_500)
      scrollback = append_all(Scrollback.new(), [data])

      assert Scrollback.text(scrollback) == data
    end

    test "does not split a multibyte codepoint across pieces" do
      data = String.duplicate("é", 2_000)
      scrollback = append_all(Scrollback.new(), [data])

      text = Scrollback.text(scrollback)

      assert String.valid?(text)
      assert text == data
    end
  end
end

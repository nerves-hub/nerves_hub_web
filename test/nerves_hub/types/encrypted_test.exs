defmodule NervesHub.Types.EncryptedTest do
  use ExUnit.Case, async: true

  alias NervesHub.Types.Encrypted

  test "a dumped value loads back as itself" do
    assert {:ok, stored} = Encrypted.dump("xoxb-a-bot-token")
    assert {:ok, "xoxb-a-bot-token"} = Encrypted.load(stored)
  end

  test "stores neither the value nor the same bytes twice" do
    {:ok, first} = Encrypted.dump("xoxb-a-bot-token")
    {:ok, second} = Encrypted.dump("xoxb-a-bot-token")

    refute first =~ "xoxb"
    refute first == second
  end

  test "refuses a stored value that was altered" do
    {:ok, <<head::binary-size(30), byte, rest::binary>>} = Encrypted.dump("xoxb-a-bot-token")

    assert :error = Encrypted.load(<<head::binary, Bitwise.bxor(byte, 1), rest::binary>>)
    assert :error = Encrypted.load("not encrypted at all")
  end

  test "only casts strings" do
    assert {:ok, "token"} = Encrypted.cast("token")
    assert :error = Encrypted.cast(42)
  end
end

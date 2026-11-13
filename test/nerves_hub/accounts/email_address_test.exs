defmodule NervesHub.Accounts.EmailAddressTest do
  use ExUnit.Case, async: true

  alias NervesHub.Accounts.EmailAddress

  describe "valid?/1" do
    test "accepts addresses gen_smtp can send to" do
      for address <- [
            "user@example.com",
            "first.last+tag@sub.example.co.uk",
            "o'brien@example.com",
            "user@localhost",
            "josé@example.com"
          ] do
        assert EmailAddress.valid?(address), "expected #{address} to be accepted"
      end
    end

    test "rejects addresses gen_smtp can't parse" do
      for address <- [
            "lil.i.a.n...lec.a.ros@gmail.com",
            ".leading@example.com",
            "trailing.@example.com",
            "user@example..com",
            "user@example.com.",
            "user(comment)@example.com",
            "no-at-sign",
            ""
          ] do
        refute EmailAddress.valid?(address), "expected #{inspect(address)} to be rejected"
      end
    end

    test "rejects anything other than one bare address" do
      for address <- ["Jane <jane@example.com>", "<jane@example.com>", "a@example.com, b@example.com"] do
        refute EmailAddress.valid?(address), "expected #{address} to be rejected"
      end
    end

    test "rejects values that aren't valid UTF-8 strings" do
      refute EmailAddress.valid?(<<0xFF, "@example.com">>)
      refute EmailAddress.valid?(nil)
    end
  end
end

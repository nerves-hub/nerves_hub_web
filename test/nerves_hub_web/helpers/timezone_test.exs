defmodule NervesHubWeb.Helpers.TimezoneTest do
  use ExUnit.Case, async: true

  alias NervesHubWeb.Helpers.Timezone

  describe "validate/1" do
    test "accepts a zone the time zone database knows" do
      assert Timezone.validate("Pacific/Auckland") == {:ok, "Pacific/Auckland"}
      assert Timezone.validate("Etc/UTC") == {:ok, "Etc/UTC"}
    end

    test "rejects anything the database doesn't recognise" do
      assert Timezone.validate("Mars/Olympus_Mons") == :error
      assert Timezone.validate("") == :error
      assert Timezone.validate(nil) == :error
      assert Timezone.validate(:"Pacific/Auckland") == :error
    end

    test "rejects an absurdly long name rather than handing it to the database" do
      assert Timezone.validate(String.duplicate("a", 200)) == :error
    end
  end

  describe "resolve/1" do
    test "returns the first recognised candidate" do
      assert Timezone.resolve([nil, "nonsense", "Europe/Berlin"]) == "Europe/Berlin"
    end

    test "falls back to UTC when nothing is recognised" do
      assert Timezone.resolve([nil, "nonsense"]) == "Etc/UTC"
      assert Timezone.resolve([]) == "Etc/UTC"
    end

    test "accepts a bare candidate" do
      assert Timezone.resolve("Europe/Berlin") == "Europe/Berlin"
      assert Timezone.resolve(nil) == "Etc/UTC"
    end
  end
end

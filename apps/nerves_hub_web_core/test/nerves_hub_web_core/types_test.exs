defmodule NervesHubWebCore.TypesTest do
  use ExUnit.Case, async: true

  alias NervesHubWebCore.Accounts.User
  alias NervesHubWebCore.Types

  describe "resource" do
    test "type" do
      assert Types.Resource.type() == :string
    end

    test "cast" do
      # Valid cast
      assert Types.Resource.cast(User) == {:ok, User}
      assert Types.Resource.cast(to_string(User)) == {:ok, User}

      # Invalid cast
      assert Types.Resource.cast("AuditLog") == :error
      assert Types.Resource.cast(NervesHubWebCore) == :error
      assert Types.Resource.cast(:wat) == :error
      assert Types.Resource.cast(1234) == :error
    end

    test "dump" do
      # Valid dump
      assert Types.Resource.dump(User) == {:ok, to_string(User)}
      assert Types.Resource.dump(to_string(User)) == {:ok, to_string(User)}

      # Invalid dump
      assert Types.Resource.dump("AuditLog") == :error
      assert Types.Resource.dump(NervesHubWebCore) == :error
      assert Types.Resource.dump(:wat) == :error
      assert Types.Resource.dump(1234) == :error
    end

    test "load" do
      assert Types.Resource.load(to_string(User)) == {:ok, User}
    end
  end
end

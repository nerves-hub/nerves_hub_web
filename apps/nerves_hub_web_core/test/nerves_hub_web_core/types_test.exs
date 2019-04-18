defmodule NervesHubWebCore.TypesTest do
  use ExUnit.Case, async: true

  alias NervesHubWebCore.Types
  alias NervesHubWebCore.AuditLogs.AuditLog

  describe "resource" do
    test "type" do
      assert Types.Resource.type() == :string
    end

    test "cast" do
      # Valid cast
      assert Types.Resource.cast(AuditLog) == {:ok, AuditLog}
      assert Types.Resource.cast(to_string(AuditLog)) == {:ok, AuditLog}

      # Invalid cast
      assert Types.Resource.cast("AuditLog") == :error
      assert Types.Resource.cast(NervesHubWebCore) == :error
      assert Types.Resource.cast(:wat) == :error
      assert Types.Resource.cast(1234) == :error
    end

    test "dump" do
      # Valid dump
      assert Types.Resource.dump(AuditLog) == {:ok, to_string(AuditLog)}
      assert Types.Resource.dump(to_string(AuditLog)) == {:ok, to_string(AuditLog)}

      # Invalid dump
      assert Types.Resource.dump("AuditLog") == :error
      assert Types.Resource.dump(NervesHubWebCore) == :error
      assert Types.Resource.dump(:wat) == :error
      assert Types.Resource.dump(1234) == :error
    end

    test "load" do
      assert Types.Resource.load(to_string(AuditLog)) == {:ok, AuditLog}
    end
  end
end

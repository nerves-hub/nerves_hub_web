defmodule NervesHub.AuditLogsTest do
  use NervesHub.DataCase

  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.AuditLog
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  describe "truncate" do
    test "delete audit log entries older than 3 days" do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)

      Fixtures.add_audit_logs(10, org.id, 10)

      assert {:ok, 7} = AuditLogs.truncate(org.id, 3)

      assert Repo.aggregate(AuditLog, :count) == 3
    end

    test "delete audit log entries older than 8 days" do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)

      Fixtures.add_audit_logs(10, org.id, 10)

      assert {:ok, 2} = AuditLogs.truncate(org.id, 8)

      assert Repo.aggregate(AuditLog, :count) == 8
    end

    test "only deletes audit log from the specified org" do
      user = Fixtures.user_fixture()

      org = Fixtures.org_fixture(user)
      org2 = Fixtures.org_fixture(user, %{name: "Test-Org2"})

      Fixtures.add_audit_logs(10, org.id, 10)
      Fixtures.add_audit_logs(100, org2.id, 10)

      assert {:ok, 7} = AuditLogs.truncate(org.id, 3)

      assert Repo.aggregate(AuditLog, :count) == 13
    end
  end
end

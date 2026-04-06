defmodule NervesHub.Ash.AuditLogs.AuditLogTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Ash.AuditLogs.AuditLog
  alias NervesHub.Fixtures

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)

    # Create audit logs via the Phoenix context
    Fixtures.add_audit_logs(10, org.id, 5)

    %{user: user, org: org}
  end

  describe "read" do
    test "default read returns audit logs", %{org: org} do
      logs = AuditLog.read!()
      assert Enum.any?(logs, &(&1.org_id == org.id))
    end

    test "list_by_org returns logs for org", %{org: org} do
      logs = AuditLog.list_by_org!(org.id)

      assert length(logs) == 5
      assert Enum.all?(logs, &(&1.org_id == org.id))
    end

    test "list_by_org only returns logs for specified org" do
      user2 = Fixtures.user_fixture()
      org2 = Fixtures.org_fixture(user2)
      Fixtures.add_audit_logs(10, org2.id, 3)

      logs = AuditLog.list_by_org!(org2.id)

      assert length(logs) == 3
      assert Enum.all?(logs, &(&1.org_id == org2.id))
    end
  end

  describe "list_by_resource" do
    test "returns logs for specific resource" do
      logs = AuditLog.list_by_resource!("devices", 10)
      assert Enum.all?(logs, &(&1.resource_id == 10))
    end
  end

  describe "create" do
    test "creates audit log entry", %{org: org} do
      log =
        AuditLog.create!(%{
          org_id: org.id,
          actor_id: 1,
          actor_type: "users",
          resource_id: 1,
          resource_type: "devices",
          description: "Test audit log"
        })

      assert log.id
      assert log.description == "Test audit log"
    end
  end
end

defmodule NervesHub.Workers.OrgAuditLogTruncationTest do
  use NervesHub.DataCase

  alias NervesHub.AuditLogs.AuditLog
  alias NervesHub.Fixtures
  alias NervesHub.Workers.OrgAuditLogTruncation

  test "delete audit log entries older than 3 days" do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)

    Fixtures.add_audit_logs(10, org.id, 10)

    assert :ok = perform_job(OrgAuditLogTruncation, %{"org_id" => org.id, "days_to_keep" => 3})

    assert Repo.aggregate(AuditLog, :count) == 3
  end
end

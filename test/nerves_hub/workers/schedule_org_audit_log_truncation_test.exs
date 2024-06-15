defmodule NervesHub.Workers.ScheduleOrgAuditLogTruncationTest do
  use NervesHub.DataCase

  alias NervesHub.Accounts
  alias NervesHub.Fixtures
  alias NervesHub.Workers.ScheduleOrgAuditLogTruncation
  alias NervesHub.Workers.OrgAuditLogTruncation

  setup do
    Application.put_env(:nerves_hub, :audit_logs, enabled: true)
    Fixtures.standard_fixture()
  end

  describe "audit log truncation disabled" do
    test "skips scheduling of audit log truncation", %{org: org} do
      Application.put_env(:nerves_hub, :audit_logs, enabled: false)

      {:ok, :disabled} = perform_job(ScheduleOrgAuditLogTruncation, %{})

      refute_enqueued(worker: OrgAuditLogTruncation, args: %{org_id: org.id})
    end
  end

  describe "audit log truncation enabled" do
    test "scheduling audit log truncation for an org" do
      {:ok, 2} = perform_job(ScheduleOrgAuditLogTruncation, %{})

      all_truncation_jobs = all_enqueued(worker: OrgAuditLogTruncation)

      assert Enum.count(all_truncation_jobs) == 2

      for org <- Accounts.get_orgs() do
        assert_enqueued(worker: OrgAuditLogTruncation, args: %{org_id: org.id})
      end
    end
  end
end

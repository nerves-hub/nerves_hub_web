defmodule NervesHub.AuditLogsTest do
  use NervesHub.DataCase, async: true

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

  describe "kind" do
    setup do
      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)

      %{user: user, org: org}
    end

    test "is stored when given", %{user: user, org: org} do
      :ok = AuditLogs.audit!(user, org, "rebooted", kind: :device_rebooted)

      assert [%AuditLog{kind: :device_rebooted}] = AuditLogs.logs_for(org)
    end

    test "is nil when not given, as on rows written before kinds", %{user: user, org: org} do
      :ok = AuditLogs.audit!(user, org, "did something")

      assert [%AuditLog{kind: nil}] = AuditLogs.logs_for(org)
    end

    test "is kept beside a reference id", %{user: user, org: org} do
      ref = Ecto.UUID.generate()

      AuditLogs.audit_with_ref!(user, org, "sent an archive", ref, kind: :archive_sent)

      assert [%AuditLog{kind: :archive_sent, reference_id: ^ref}] = AuditLogs.logs_for(org)
    end

    test "rejects a kind it doesn't know", %{user: user, org: org} do
      changeset = user |> AuditLog.build(org, "did something", kind: :made_up) |> AuditLog.changeset()

      refute changeset.valid?
      assert {_, error} = changeset.errors[:kind]
      assert error[:validation] == :inclusion
    end
  end
end

defmodule NervesHub.AuditLogsTest do
  use NervesHub.DataCase

  alias NervesHub.AuditLogs
  alias NervesHub.Devices.Device
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  describe "truncate logs" do
    test "keeps a max amount of days" do
      now = NaiveDateTime.utc_now()

      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)

      Enum.map(0..5, fn days ->
        inserted_at = NaiveDateTime.add(now, -1 * days * 24 * 60 * 60, :second)

        AuditLogs.audit!(%Device{id: 10}, %Device{id: 10, org_id: org.id}, :update, "Updating")
        |> Ecto.Changeset.change(%{inserted_at: inserted_at})
        |> Repo.update!()
      end)

      AuditLogs.truncate(%{max_records_per_run: 10, days_kept: 3})

      assert Enum.count(Repo.all(AuditLogs.AuditLog)) == 3
    end

    test "limits amount deleted" do
      now = NaiveDateTime.utc_now()

      user = Fixtures.user_fixture()
      org = Fixtures.org_fixture(user)

      # Create 12 records from 5 days ago
      Enum.map(0..11, fn _ ->
        inserted_at = NaiveDateTime.add(now, -1 * 5 * 24 * 60 * 60, :second)

        AuditLogs.audit!(%Device{id: 10}, %Device{id: 10, org_id: org.id}, :update, "Updating")
        |> Ecto.Changeset.change(%{inserted_at: inserted_at})
        |> Repo.update!()
      end)

      AuditLogs.truncate(%{max_records_per_run: 10, days_kept: 3})

      assert Enum.count(Repo.all(AuditLogs.AuditLog)) == 2
    end
  end
end

defmodule NervesHub.Repo.Migrations.NullTrueOnActionAndParamsForAuditLogs do
  use Ecto.Migration

  def change do
    execute(
      "ALTER TABLE audit_logs ALTER COLUMN action DROP NOT NULL",
      "ALTER TABLE audit_logs ALTER COLUMN action SET NOT NULL"
    )

    execute(
      "ALTER TABLE audit_logs ALTER COLUMN params DROP NOT NULL",
      "ALTER TABLE audit_logs ALTER COLUMN params SET NOT NULL"
    )
  end
end

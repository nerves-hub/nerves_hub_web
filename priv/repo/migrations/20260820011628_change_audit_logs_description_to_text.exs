defmodule NervesHub.Repo.Migrations.ChangeAuditLogsDescriptionToText do
  use Ecto.Migration

  # varchar(255) -> text is binary coercible, so this is a catalog only change:
  # no table rewrite, and nothing indexes `description`. It still needs a brief
  # ACCESS EXCLUSIVE lock, so fail fast rather than queueing behind long reads.
  def up() do
    execute("SET lock_timeout = '5s'")
    execute("ALTER TABLE audit_logs ALTER COLUMN description TYPE text")
  end

  def down() do
    execute("SET lock_timeout = '5s'")

    execute("""
    ALTER TABLE audit_logs
    ALTER COLUMN description TYPE varchar(255) USING left(description, 255)
    """)
  end
end

defmodule NervesHub.Repo.Migrations.AddLogRetentionLimitToOrgs do
  use Ecto.Migration

  def change do
    alter table("orgs") do
      add :audit_log_days_to_keep, :integer
    end
  end
end

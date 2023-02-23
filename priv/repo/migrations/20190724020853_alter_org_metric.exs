defmodule NervesHub.Repo.Migrations.AlterOrgMetric do
  use Ecto.Migration

  def change do
    alter table("org_metrics") do
      modify :bytes_stored, :bigint
      remove :bytes_transferred
    end
  end
end

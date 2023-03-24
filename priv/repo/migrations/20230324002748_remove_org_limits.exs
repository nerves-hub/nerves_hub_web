defmodule NervesHub.Repo.Migrations.RemoveOrgLimits do
  use Ecto.Migration

  def up do
    drop table(:org_limits)
  end

  def down do
    raise "One way migration"
  end
end

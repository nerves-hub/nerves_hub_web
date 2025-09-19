defmodule NervesHub.Repo.Migrations.AddOrgSettings do
  use Ecto.Migration

  def change() do
    alter table("orgs") do
      add(:settings, :map)
    end
  end
end

defmodule NervesHub.Repo.Migrations.RemoveLastCommunicationFromDevices do
  use Ecto.Migration

  # Since this removes a column, it should typically be applied in a separate
  # deploy for multi-node setups in order to prevent errors between old nodes
  # going down and new ones coming up.
  #
  # See https://fly.io/phoenix-files/migration-recipes/#removing-a-column
  #
  # You can accomplish this in releases with:
  #   Nerves.Release.Tasks.migrate([{NervesHub.Repo, [to_exclusive: 20240711034640]}])

  def up do
    alter table(:devices) do
      remove_if_exists :last_communication, :utc_datetime
    end
  end

  def down do
    alter table(:devices) do
      add_if_not_exists :last_communication, :utc_datetime
    end
  end
end

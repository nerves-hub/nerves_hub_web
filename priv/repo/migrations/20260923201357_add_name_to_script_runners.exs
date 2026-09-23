defmodule NervesHub.Repo.Migrations.AddNameToScriptRunners do
  use Ecto.Migration

  # A run's own name, so a listing can be read without reading everyone's code.
  # `text` is ad-hoc and often long, which made it a poor label for the one
  # column a person scans.
  def up() do
    alter table(:script_runners) do
      add(:name, :string)
    end

    # Runs that predate the column have no name anyone chose, so they are given
    # one derived from what identified them until now: when they ran. Done before
    # the NOT NULL below, which would otherwise reject them.
    execute("""
    UPDATE script_runners
    SET name = 'Script run ' || to_char(inserted_at, 'YYYY-MM-DD HH24:MI')
    WHERE name IS NULL
    """)

    alter table(:script_runners) do
      modify(:name, :string, null: false)
    end
  end

  def down() do
    alter table(:script_runners) do
      remove(:name)
    end
  end
end

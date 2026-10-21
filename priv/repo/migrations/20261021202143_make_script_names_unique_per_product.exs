defmodule NervesHub.Repo.Migrations.MakeScriptNamesUniquePerProduct do
  @moduledoc """
  Give each support script in a product its own name.

  Scripts are run on devices by name, from the API and from Slack, but nothing
  stopped two scripts in a product from sharing one. When they did, the lookup
  matched both and raised instead of running either.

  Existing duplicates are renamed before the index is created: the oldest
  script keeps the name, which is the one the name ran before the duplicate
  appeared, and each newer one has its id appended, as in `reboot (412)`. The
  name is trimmed to make room for the suffix where it would otherwise pass the
  column's 255 characters.

  The table is locked against other writers first, so a duplicate created while
  this runs cannot fail the index. Rolling back drops the index but leaves the
  renamed scripts as they are, since nothing records what they were called.
  """

  use Ecto.Migration

  def up() do
    execute("LOCK TABLE scripts IN SHARE ROW EXCLUSIVE MODE")

    execute("""
    UPDATE scripts AS s
    SET name = left(s.name, 255 - length(' (' || s.id || ')')) || ' (' || s.id || ')'
    WHERE EXISTS (
      SELECT 1 FROM scripts AS older
      WHERE older.product_id = s.product_id
        AND older.name = s.name
        AND older.id < s.id
    )
    """)

    create(unique_index(:scripts, [:product_id, :name]))
  end

  def down() do
    drop(unique_index(:scripts, [:product_id, :name]))
  end
end

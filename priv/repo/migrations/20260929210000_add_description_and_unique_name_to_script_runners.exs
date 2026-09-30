defmodule NervesHub.Repo.Migrations.AddDescriptionAndUniqueNameToScriptRunners do
  use Ecto.Migration

  def change() do
    alter table(:script_runners) do
      # Operator commentary on the run -- why it was run, what to make of the
      # results. Unlike `text`, this is not a record of what happened and stays
      # editable after the run is over. Nullable: runs are created without one.
      add(:description, :text)
    end

    # A name identifies a run within its product, so two runs cannot share one.
    # Scoped to the product rather than global, the same way deployment groups and
    # support scripts are: two products naming a run "Reboot fleet" are talking
    # about different fleets.
    #
    # No backfill of existing duplicates: the feature is unreleased, so there are
    # no rows in the wild that this could reject.
    create(unique_index(:script_runners, [:product_id, :name]))
  end
end

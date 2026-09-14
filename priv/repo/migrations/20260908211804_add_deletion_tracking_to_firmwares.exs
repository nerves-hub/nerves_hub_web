defmodule NervesHub.Repo.Migrations.AddDeletionTrackingToFirmwares do
  @moduledoc """
  Give firmware a soft delete, so deleting it stops meaning destroying history.

  Three tables reference `firmwares` with `ON DELETE NO ACTION`, and
  `device_firmwares` is the one that matters: every device that has ever
  reported a firmware version holds a row there, so any firmware that actually
  shipped could not be deleted at all. Keeping the row and marking it deleted
  is what makes deletion possible without losing the record of what a device
  once ran.

  `deleted_by_id` is nullable and nilified rather than restricted: a deleter
  whose account is later removed must not make the firmware unreadable.
  """

  use Ecto.Migration

  def change() do
    alter table(:firmwares) do
      add(:deleted_at, :utc_datetime, null: true)
      add(:deleted_by_id, references(:users, on_delete: :nilify_all), null: true)
    end

    # Every firmware listing is scoped to a product and now also filters out
    # the deleted rows.
    create(index(:firmwares, [:product_id, :deleted_at]))

    # Every foreign key in this schema carries an index; `index_test.exs`
    # enforces it.
    create(index(:firmwares, [:deleted_by_id]))
  end
end

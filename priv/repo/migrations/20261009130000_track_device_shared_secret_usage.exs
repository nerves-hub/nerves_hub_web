defmodule NervesHub.Repo.Migrations.TrackDeviceSharedSecretUsage do
  @moduledoc """
  Record when a device last connected with each of its shared secrets, and who
  created and deactivated it.

  The user references are restricted rather than nilified, so the record of
  who issued or revoked a credential cannot be lost. Users are soft deleted,
  so this never blocks removing an account.
  """

  use Ecto.Migration

  def change() do
    alter table(:device_shared_secret_auths) do
      add(:last_used, :utc_datetime)
      add(:created_by_id, references(:users), null: true)
      add(:deactivated_by_id, references(:users), null: true)
    end

    # Every foreign key in this schema carries an index; `index_test.exs`
    # enforces it.
    create(index(:device_shared_secret_auths, [:created_by_id]))
    create(index(:device_shared_secret_auths, [:deactivated_by_id]))
  end
end

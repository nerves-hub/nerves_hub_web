defmodule NervesHub.Repo.Migrations.CreateNetworkIdentities do
  use Ecto.Migration

  def change() do
    create table(:network_identities) do
      # The organisation this identity speaks for. Not derived from the owner at
      # read time, because the relay authorization path resolves a key straight
      # to an organisation and the identities page lists an organisation's keys —
      # both want an indexed column rather than a join.
      #
      # It has to be kept true rather than merely set: a device that moved
      # organisation and left a stale row here would be admitted to its former
      # customer's network. `NervesHub.Devices.move/3` updates it in the same
      # transaction that moves the device.
      add(:org_id, references(:orgs, on_delete: :delete_all), null: false)

      # At most one of the two below. Both null is an identity an operator
      # recorded by hand, belonging to the organisation and nothing else in it.
      add(:device_id, references(:devices, on_delete: :delete_all))

      # The membership, not the user. A person in three organisations holds three
      # identities, each scoped to the one it speaks for, and removing them from
      # an organisation takes their access to that network with it.
      add(:org_user_id, references(:org_users, on_delete: :delete_all))

      add(:service, :string, null: false)

      # Which endpoint of that service this is. One owner can run two iroh
      # endpoints — a console and an application, say — each holding its own key.
      #
      # NOT NULL with a default is load bearing: a nullable column silently
      # defeats the unique indexes below, because NULL != NULL in Postgres, so
      # the duplicates they exist to prevent would insert without any error.
      add(:instance, :string, null: false, default: "default")

      add(:identifier, :string, null: false)
      add(:details, :map, null: false, default: %{})
      add(:source, :string, null: false, default: "device_reported")
      add(:last_reported_at, :utc_datetime)

      timestamps()
    end

    # No two owners may claim the same key, anywhere. This is what makes the
    # table a registry rather than a set of per-owner lists: a key resolves to
    # one organisation, so the relay never has two answers to choose between.
    #
    # It also surfaces a cloned SD card, where a whole batch boots holding the
    # identity of the device that was imaged.
    create(unique_index(:network_identities, [:service, :identifier]))

    # One identity per endpoint per owner. Partial, because the owner columns are
    # nullable and a plain composite index would let every operator-recorded row
    # collide silently — the same NULL != NULL trap as `instance` above, which is
    # why that column is not nullable.
    create(
      unique_index(:network_identities, [:device_id, :service, :instance],
        where: "device_id IS NOT NULL",
        name: :network_identities_device_service_instance_index
      )
    )

    create(
      unique_index(:network_identities, [:org_user_id, :service, :instance],
        where: "org_user_id IS NOT NULL",
        name: :network_identities_org_user_service_instance_index
      )
    )

    # Listing an organisation's identities is the page this exists to serve.
    create(index(:network_identities, [:org_id]))

    # Plain indexes on the owner columns as well as the partial unique ones
    # above. Postgres does not use a partial index to find rows for a cascading
    # delete, so without these, removing a device or a membership scans the
    # table. NervesHub.Database.IndexTest checks every foreign key has one.
    create(index(:network_identities, [:device_id]))
    create(index(:network_identities, [:org_user_id]))

    # An identity belongs to a device, or to a membership, or to neither. Never
    # both: the two owners could disagree about which organisation it belongs to,
    # and that answer has to be unambiguous.
    create(
      constraint(:network_identities, :network_identities_one_owner,
        check: "NOT (device_id IS NOT NULL AND org_user_id IS NOT NULL)"
      )
    )
  end
end

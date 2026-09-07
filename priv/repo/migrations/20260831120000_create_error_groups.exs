defmodule NervesHub.Repo.Migrations.CreateErrorGroups do
  use Ecto.Migration

  def change() do
    create table(:error_groups) do
      # Product-scoped, not org-scoped. The organisation is reachable through
      # the product, and a denormalised org_id here would be one more column
      # that has to be kept true when a device moves — see the notes on
      # `network_identities.org_id` for what that costs. Nothing on this table
      # is read without a product in hand.
      add(:product_id, references(:products, on_delete: :delete_all), null: false)

      # What ties this row to its occurrences in ClickHouse. Computed by
      # `NervesHub.ErrorReports.Fingerprint` from the kind, the normalised
      # reason and the top frames — or supplied by the device, for a report
      # that knows its own grouping better than a stacktrace does.
      add(:fingerprint, :string, null: false)

      # Which revision of the fingerprint algorithm produced it. Grouping is the
      # part of this feature most likely to need adjustment once real data
      # arrives, and this is what makes adjusting it safe: a bumped version
      # groups new occurrences into new rows instead of silently re-grouping
      # history against a rule that no longer produced it.
      add(:fingerprint_version, :integer, null: false, default: 1)

      add(:kind, :string, null: false)
      add(:source, :string, null: false, default: "logger")
      add(:reason, :text, null: false)

      # The innermost frame, denormalised so the list page renders without
      # reaching into ClickHouse for every row.
      add(:top_frame_module, :string)
      add(:top_frame_function, :string)
      add(:top_frame_file, :string)
      add(:top_frame_line, :integer)

      add(:status, :string, null: false, default: "unresolved")

      # Kept here rather than counted from ClickHouse because it has to outlive
      # the occurrences. They are dropped by TTL after 30 days; "this has
      # happened forty thousand times since March" should still be answerable
      # in June.
      add(:occurrence_count, :bigint, null: false, default: 0)

      add(:first_seen_at, :utc_datetime_usec, null: false)
      add(:last_seen_at, :utc_datetime_usec, null: false)
      add(:first_seen_firmware_uuid, :string)
      add(:last_seen_firmware_uuid, :string)

      add(:resolved_at, :utc_datetime_usec)
      add(:resolved_by_id, references(:users, on_delete: :nilify_all))

      # Recorded but unused in v1. Today any occurrence after `resolved_at`
      # reopens the group, which on a fleet still part-way through an update
      # means it reopens immediately. The refinement — reopen only for firmware
      # built after the fix — needs this column, so it is here from the start
      # and the change will not need a migration.
      add(:resolved_in_firmware_uuid, :string)

      add(:regressed_at, :utc_datetime_usec)

      add(:muted_at, :utc_datetime_usec)
      add(:muted_by_id, references(:users, on_delete: :nilify_all))

      timestamps()
    end

    # The conflict target for the coalescing upsert in
    # `NervesHub.ErrorReports.GroupBuffer`, and what makes a fingerprint mean
    # one issue per product rather than one per report.
    create(unique_index(:error_groups, [:product_id, :fingerprint]))

    # The product page's default read: unresolved issues, most recent first.
    create(index(:error_groups, [:product_id, :status, :last_seen_at]))

    # Both owners are `nilify_all`, so deleting a user updates every row that
    # names them. Without these that is a sequential scan, and
    # `NervesHub.Database.IndexTest` checks for exactly this.
    create(index(:error_groups, [:resolved_by_id]))
    create(index(:error_groups, [:muted_by_id]))
  end
end

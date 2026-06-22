defmodule NervesHub.Database.IndexTest do
  @moduledoc """
  Verify all expected indexes exist

  To run tests:
  mix test test/nerves_hub/database/index_test.exs
  """

  use NervesHub.DataCase, async: true

  alias Ecto.Adapters.SQL
  alias NervesHub.Repo

  # These FK indexes are known to be missing and are excluded from the check.
  # This test is meant as a reminder to consider missing indexes as new tables/columns are added.
  # Only add to this list if you are certain the index isn't needed!
  # quokka:sort
  @known_missing_fk_indexes [
    "archives.org_key_id",
    "ca_certificates.org_id",
    "deployment_releases.created_by_id",
    "deployments.org_id",
    "device_certificates.org_id",
    "device_firmwares.firmware_id",
    "device_shared_secret_auths.device_id",
    "device_shared_secret_auths.product_shared_secret_auth_id",
    "devices.current_device_firmware_id",
    "devices.org_id",
    "firmware_deltas.target_id",
    "firmware_transfers.org_id",
    "firmwares.org_id",
    "firmwares.org_key_id",
    "inflight_deployment_checks.deployment_id",
    "inflight_deployment_checks.device_id",
    "inflight_updates.firmware_id",
    "invites.invited_by_id",
    "invites.org_id",
    "jitp.product_id",
    "latest_device_connections.org_id",
    "latest_device_connections.product_id",
    "org_keys.created_by_id",
    "org_users.org_id",
    "org_users.user_id",
    "pinned_devices.device_id",
    "pinned_devices.user_id",
    "product_shared_secret_auth.product_id",
    "product_users.user_id",
    "scripts.created_by_id",
    "scripts.last_updated_by_id",
    "scripts.product_id",
    "user_tokens.user_id"
  ]

  describe "Check for missing FK indexes" do
    test "Verify we have no missing FK indexes on main database" do
      # cspell: disable
      %Postgrex.Result{rows: rows} =
        SQL.query!(
          Repo,
          """
          WITH y AS (
          SELECT
            pg_catalog.format('%I', c1.relname)  AS referencing_tbl,
            pg_catalog.quote_ident(a1.attname) AS referencing_column
          FROM pg_catalog.pg_constraint t
          JOIN pg_catalog.pg_attribute  a1 ON a1.attrelid = t.conrelid AND a1.attnum = t.conkey[1]
          JOIN pg_catalog.pg_class      c1 ON c1.oid = t.conrelid
          JOIN pg_catalog.pg_namespace  n1 ON n1.oid = c1.relnamespace
          JOIN pg_catalog.pg_class      c2 ON c2.oid = t.confrelid
          JOIN pg_catalog.pg_namespace  n2 ON n2.oid = c2.relnamespace
          JOIN pg_catalog.pg_attribute  a2 ON a2.attrelid = t.confrelid AND a2.attnum = t.confkey[1]
          WHERE t.contype = 'f'
          AND NOT EXISTS (
            SELECT 1
            FROM pg_catalog.pg_index i
            WHERE i.indrelid = t.conrelid
            AND i.indkey[0] = t.conkey[1]
            AND i.indpred IS NULL
          )
          )
          SELECT  referencing_tbl || '.' || referencing_column as column
          FROM y
          ORDER BY 1;
          """,
          []
        )

      # cspell: enable

      unexpected_missing =
        rows
        |> Enum.map(fn [col] -> col end)
        |> Enum.reject(&(&1 in @known_missing_fk_indexes))

      assert unexpected_missing == []
    end
  end
end

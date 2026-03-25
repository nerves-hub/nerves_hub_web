defmodule NervesHub.Database.IndexTest do
  @moduledoc """
  Verify all expected indexes exist

  To run tests:
  mix test test/nerves_hub/database/index_test.exs
  """

  use NervesHub.DataCase, async: true

  alias Ecto.Adapters.SQL
  alias NervesHub.Repo

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

      assert rows == []
    end
  end
end

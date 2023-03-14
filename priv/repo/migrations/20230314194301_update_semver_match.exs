defmodule NervesHub.Repo.Migrations.UpdateSemverMatch do
  use Ecto.Migration

  def change do
    execute """
    CREATE OR REPLACE FUNCTION semver_match(version text, req text) RETURNS boolean
    LANGUAGE SQL
    IMMUTABLE
    RETURNS NULL ON NULL INPUT
    AS $$
    SELECT CASE
    WHEN version LIKE '%-%' THEN 'f'
    WHEN req LIKE '~>%' THEN
        string_to_array(version, '.')::int[] >= string_to_array(substring(req from 4), '.')::int[]
        AND
        string_to_array(version, '.')::int[] <
        -- increment last item by one. (X.Y.Z => X.Y.(Z+1))
        array_append(
            (string_to_array(substring(req from 4), '.')::int[])[1:(array_length(string_to_array(req, '.'), 1) - 1)], -- X.Y
            (string_to_array(substring(req from 4), '.')::int[])[array_length(string_to_array(req, '.'), 1)] + 1 -- Z + 1
        )
    WHEN req LIKE '>=%' THEN string_to_array(version, '.')::int[] >= string_to_array(substring(req from 4), '.')::int[]
    WHEN req LIKE '<=%' THEN string_to_array(version, '.')::int[] <= string_to_array(substring(req from 4), '.')::int[]
    WHEN req LIKE '>%' THEN string_to_array(version, '.')::int[] > string_to_array(substring(req from 3), '.')::int[]
    WHEN req LIKE '<%' THEN string_to_array(version, '.')::int[] < string_to_array(substring(req from 3), '.')::int[]
    WHEN req LIKE '=%' THEN
        (string_to_array(version, '.')::int[])[1:array_length(string_to_array(substring(req from 3), '.'), 1)] =
        string_to_array(substring(req from 3), '.')::int[]
    ELSE NULL
    END $$;
    """, "drop function if exists semver_match;"
  end
end

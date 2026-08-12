defmodule NervesHub.Repo.Migrations.AddSemverSortKeyFunction do
  use Ecto.Migration

  # Adds `semver_sort_key(text)`: maps a semver string to a text key whose plain
  # lexical (`<`/`>`) ordering reproduces SemVer 2.0.0 precedence. It lets us use
  # a single, index-backed expression for both ORDER BY and range WHERE clauses
  # instead of the ICU `numeric` collation (mis-sorts pre-releases) and the
  # hand-rolled `semver_match` plpgsql (diverges from Elixir's `Version`).
  #
  # Encoding:
  #   * major/minor/patch are zero-padded to fixed width so digit runs compare
  #     numerically;
  #   * a release gets the sentinel `{` (0x7B) appended and a pre-release gets `-`
  #     (0x2D) — since `-` < `{`, a pre-release sorts *before* its release
  #     (SemVer §11: a release has higher precedence than its pre-releases);
  #   * within the pre-release, numeric identifiers are tagged `0` and padded,
  #     alphanumeric identifiers are tagged `1`, so numeric < alphanumeric and a
  #     shorter identifier set sorts before a longer one (SemVer §11.4).
  #
  # The function is STRICT and built on `regexp_match/2`, which returns NULL (it
  # does not raise) for any non-semver input — so a malformed, device-reported
  # version yields a NULL key rather than erroring a query or a write. NULL keys
  # must be ordered with `NULLS LAST` at each call site.
  #
  # COLLATION — REQUIRED at every call site. The key relies on plain byte
  # ordering (the `-` (0x2D) < `{` (0x7B) sentinel is what makes a pre-release
  # sort before its release). Postgres compares/ORDERs `text` under the database
  # collation, which here is `en_US.utf8` — a locale collation that mis-weights
  # the hyphen and *inverts* the pre-release/release order. Every comparison and
  # ORDER BY on the key, and the backing index, MUST be `COLLATE "C"`, e.g.
  #   ORDER BY semver_sort_key(version) COLLATE "C" DESC NULLS LAST
  #   WHERE semver_sort_key(a) COLLATE "C" <= semver_sort_key(b) COLLATE "C"
  #   CREATE INDEX ... ON t ((semver_sort_key(version) COLLATE "C") DESC NULLS LAST)
  # Without `COLLATE "C"` the ordering is silently wrong for pre-releases.
  #
  # Validity note: the `\d+` groups accept a leading zero (e.g. `01.2.3`) that
  # Elixir's `Version.parse/1` rejects. Firmware/Archive versions are validated
  # with `Version.parse/1` at the schema boundary, so stored versions never hit
  # that divergence; device-reported metadata is the only uncontrolled input and
  # a bad value is simply quarantined via a NULL key.
  def change() do
    execute(
      ~S"""
      CREATE OR REPLACE FUNCTION semver_sort_key(v text) RETURNS text
      LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE AS $$
        SELECT lpad(m[1],10,'0')||'.'||lpad(m[2],10,'0')||'.'||lpad(m[3],10,'0')
            || coalesce('-' || (
                 SELECT string_agg(
                          CASE WHEN id ~ '^\d+$' THEN '0'||lpad(id,10,'0') ELSE '1'||id END,
                          '.' ORDER BY ord)
                 FROM unnest(string_to_array(m[4],'.')) WITH ORDINALITY AS t(id, ord)
               ), '{')
        FROM regexp_match(v, '^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$') AS m
      $$;
      """,
      "DROP FUNCTION IF EXISTS semver_sort_key(text);"
    )
  end
end

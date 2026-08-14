defmodule NervesHub.SemverSortKeyTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Repo

  # Corpus of valid (Version.parse/1-parseable) semver strings covering releases,
  # pre-releases (alpha/beta/rc, numeric + dotted + mixed identifiers) and build
  # metadata (which must be ignored for precedence).
  @versions [
    "0.0.1",
    "0.1.0",
    "0.9.9",
    "1.0.0",
    "1.0.1",
    "1.2.0",
    "1.9.0",
    "1.10.0",
    "1.10.2",
    "2.0.0",
    "10.0.0",
    "1.0.0-alpha",
    "1.0.0-alpha.1",
    "1.0.0-alpha.beta",
    "1.0.0-beta",
    "1.0.0-beta.2",
    "1.0.0-beta.11",
    "1.0.0-rc.1",
    "1.0.0-rc1",
    "1.0.0-1",
    "1.0.0-1.2",
    "2.0.0-rc.1",
    "1.2.3+build.5",
    "1.2.3+build.9",
    "1.0.0-rc.1+build"
  ]

  # semver comparator -> the equivalent Postgres operator on the sort key.
  @op_to_sql %{">=" => ">=", ">" => ">", "<" => "<", "<=" => "<=", "==" => "="}

  defp sort_key(version) do
    {:ok, %{rows: [[key]]}} = Repo.query("SELECT semver_sort_key($1)", [version])
    key
  end

  # Fetch all sort keys in one round-trip and return a version -> key map.
  defp sort_keys(versions) do
    placeholders = versions |> Enum.with_index(1) |> Enum.map_join(",", fn {_, i} -> "($#{i})" end)
    sql = "SELECT v, semver_sort_key(v) FROM (VALUES #{placeholders}) AS t(v)"
    {:ok, %{rows: rows}} = Repo.query(sql, versions)
    Map.new(rows, fn [v, k] -> {v, k} end)
  end

  # Byte-order comparison of two keys, which is exactly Postgres `COLLATE "C"`.
  # Elixir binary comparison (`<`/`>`) is byte-wise, so we can compare in Elixir.
  defp key_compare(ka, kb) do
    cond do
      ka < kb -> :lt
      ka > kb -> :gt
      true -> :eq
    end
  end

  describe "semver_sort_key/1 ordering" do
    test "byte-order (COLLATE \"C\") key comparison matches Version.compare/2 for every pair" do
      keys = sort_keys(@versions)

      for a <- @versions, b <- @versions do
        assert key_compare(keys[a], keys[b]) == Version.compare(a, b),
               "sort-key order for #{a} vs #{b} was #{key_compare(keys[a], keys[b])}, " <>
                 "but Version.compare says #{Version.compare(a, b)}"
      end
    end

    test "ORDER BY semver_sort_key(v) COLLATE \"C\" reproduces Enum.sort(_, Version)" do
      # Feed the corpus to Postgres unordered and let the DB sort it.
      params = @versions

      placeholders =
        @versions
        |> Enum.with_index(1)
        |> Enum.map_join(",", fn {_v, i} -> "($#{i})" end)

      sql = """
      SELECT v FROM (VALUES #{placeholders}) AS t(v)
      ORDER BY semver_sort_key(v) COLLATE "C" ASC NULLS LAST
      """

      {:ok, %{rows: rows}} = Repo.query(sql, params)
      db_order = List.flatten(rows)

      # The DB order must be a valid ascending Version sort: every adjacent pair
      # is non-decreasing. (An `==` assertion against Enum.sort would be too
      # strict — semver-equal versions that differ only in build metadata, e.g.
      # "1.0.0-rc.1" and "1.0.0-rc.1+build", get the same key and may tie in
      # either order.)
      for [a, b] <- Enum.chunk_every(db_order, 2, 1, :discard) do
        assert Version.compare(a, b) in [:lt, :eq],
               "DB ordered #{a} before #{b}, but Version.compare says #{Version.compare(a, b)}"
      end
    end
  end

  describe "semver_sort_key/1 matching (equivalent to Version.match?/2, default allow_pre: true)" do
    # Single-comparator requirements translate directly to a key comparison.
    # (`~>` and compound `and`/`or` requirements are handled by the PR5
    # requirement->range translator and covered by its own tests.)
    cases = [
      {"1.5.0-rc1", ">=", "1.2.0"},
      {"1.0.0-rc", ">=", "1.0.0"},
      {"1.0.0", ">=", "1.0.0"},
      {"1.0.0-alpha", ">=", "1.0.0-alpha"},
      {"1.0.0-beta", ">=", "1.0.0-alpha"},
      {"1.0.0-alpha", ">=", "1.0.0-beta"},
      {"1.2.0", ">", "1.2.0"},
      {"1.2.1", ">", "1.2.0"},
      {"1.10.0", ">", "1.9.0"},
      {"1.0.0", "<", "1.0.0"},
      {"1.0.0-rc", "<", "1.0.0"},
      {"1.0.0", "<=", "1.0.0"},
      {"2.0.0", "<=", "1.0.0"},
      {"1.2.3+build.5", "==", "1.2.3"},
      {"1.2.3", "==", "1.2.4"}
    ]

    for {version, op, bound} <- cases do
      requirement = "#{op} #{bound}"

      test "semver_sort_key(#{version}) #{op} semver_sort_key(#{bound}) == Version.match?/2" do
        sql_op = @op_to_sql[unquote(op)]

        {:ok, %{rows: [[sql_result]]}} =
          Repo.query(
            ~s{SELECT semver_sort_key($1) COLLATE "C" #{sql_op} semver_sort_key($2) COLLATE "C"},
            [unquote(version), unquote(bound)]
          )

        assert sql_result == Version.match?(unquote(version), unquote(requirement)),
               "#{unquote(version)} #{unquote(requirement)}: sort-key predicate=#{sql_result}, " <>
                 "Version.match?=#{Version.match?(unquote(version), unquote(requirement))}"
      end
    end
  end

  describe "semver_sort_key/1 robustness" do
    test "returns NULL (does not raise) for non-semver input" do
      for bad <- ["main", "1.x", "1.0", "1.2.3.4", "", "v1.2.3", "latest"] do
        assert sort_key(bad) == nil, "expected NULL key for #{inspect(bad)}"
      end
    end

    test "COLLATE \"C\" is required: a pre-release sorts before its release only under C" do
      # Guards the design contract in the migration: on a locale-collated database
      # the key MUST be compared with COLLATE "C". This asserts the C behaviour we
      # depend on at every call site.
      {:ok, %{rows: [[c_lt]]}} =
        Repo.query(
          ~s{SELECT semver_sort_key($1) COLLATE "C" < semver_sort_key($2) COLLATE "C"},
          ["1.0.0-rc1", "1.0.0"]
        )

      assert c_lt == true
    end
  end
end

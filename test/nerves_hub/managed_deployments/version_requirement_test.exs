defmodule NervesHub.ManagedDeployments.VersionRequirementTest do
  # The database's answer has to agree with `Version`'s, or a device the
  # summary page counts as matching is moved in, then moved out again by
  # `verify_deployment_group_membership/1` when it connects.
  use NervesHub.DataCase, async: true

  import ExUnit.CaptureIO

  alias NervesHub.ManagedDeployments.VersionRequirement

  @versions [
    "0.0.0",
    "0.1.0",
    "0.9.9",
    "1.0.0-0",
    "1.0.0-alpha",
    "1.0.0-alpha.1",
    "1.0.0-alpha.beta",
    "1.0.0-beta",
    "1.0.0-beta.2",
    "1.0.0-beta.11",
    "1.0.0-rc.1",
    "1.0.0",
    "1.0.0+build.1",
    "1.0.0-rc.1+build.1",
    "1.0.1",
    "1.0.10",
    "1.1.0-dev",
    "1.1.0",
    "1.2.3",
    "1.10.0",
    "2.0.0-0",
    "2.0.0-rc.0",
    "2.0.0-rc.1",
    "2.0.0",
    "2.0.5-dev",
    "2.0.5",
    "2.1.0-dev",
    "2.1.0",
    "2.1.3",
    "2.1.6-dev",
    "2.2.0-dev",
    "2.2.0",
    "2.9.9",
    "3.0.0-alpha",
    "3.0.0",
    "10.0.0",
    "9999999999.0.0"
  ]

  # `Version.parse/1` refuses all of these, so none may match anything.
  @invalid_versions [
    "",
    "1",
    "1.0",
    "v1.0.0",
    " 1.0.0",
    "1.0.0 ",
    "01.0.0",
    "1.00.0",
    "1.0.0-",
    "1.0.0-01",
    "1.0.0-rc.01",
    "1.0.0-a..b",
    "1.0.0+",
    "1.0.0.0",
    "not-semver"
  ]

  @requirements [
    "1.0.0",
    "== 1.0.0",
    "==1.0.0",
    "== 1.0.0-rc.1",
    "== 1.0.0+build.9",
    "> 1.0.0",
    ">= 1.0.0",
    "< 1.0.0",
    "<= 1.0.0",
    "> 1.0.0-rc.1",
    ">= 1.0.0-alpha",
    "< 2.0.0",
    "<= 2.0.0-rc.0",
    "  >=   1.0.0  ",
    "~> 2.0",
    "~> 2.1",
    "~>2.1",
    "~> 2.0.0",
    "~> 2.1.3",
    "~> 2.1.3-dev",
    "~> 2.1-dev",
    "~> 2.0.0-rc.1",
    "~> 2.0.0-rc.1+build",
    "~> 1.0.0+build",
    "~> 0.1",
    ">= 1.0.0 and < 2.0.0",
    "> 1.0.0 and < 1.1.0 and != 1.0.1",
    ">= 1.0.0 or == 0.1.0",
    "== 1.0.0 or == 2.0.0 and == 3.0.0",
    "== 9.0.0 and == 3.0.0 or == 3.0.0",
    "~> 1.0 or ~> 3.0",
    "< 1.0.0 or > 2.0.0 and < 2.2.0",
    "!= 1.0.0",
    "!1.0.0"
  ]

  test "matches what `Version.match?/2` matches" do
    versions = @versions ++ @invalid_versions

    mismatches =
      for requirement <- @requirements,
          {version, matched?} <- matched_in_the_database(versions, requirement),
          matched? != version_match?(version, requirement) do
        {version, requirement, database: matched?}
      end

    assert mismatches == []
  end

  test "a device version that isn't valid SemVer matches nothing" do
    for requirement <- @requirements do
      assert matching(@invalid_versions, requirement) == []
    end
  end

  test "a device with no version matches nothing" do
    query =
      from(v in fragment("SELECT jsonb_build_object() AS firmware_metadata"),
        select: v.firmware_metadata
      )

    assert query |> VersionRequirement.where_matches(">= 0.0.0") |> Repo.all() == []
  end

  test "raises on a requirement `Version` can't parse" do
    for requirement <- ["> 1.0", "~> 2", "1.2", ">= 1.0.0 && < 2.0.0", "or", ">= 1.0.0 and"] do
      assert_raise Version.InvalidRequirementError, fn ->
        VersionRequirement.where_matches(versions_query(["1.0.0"]), requirement)
      end
    end
  end

  describe "where the database differs from `Version`, as documented" do
    test "a device version with a number longer than 10 digits never matches" do
      assert version_match?("12345678901.0.0", ">= 1.0.0")
      assert matching(["12345678901.0.0"], ">= 1.0.0") == []
    end

    test "a hyphen in a pre-release identifier orders by byte" do
      assert Version.compare("1.0.0-a.x", "1.0.0-a-b") == :lt

      assert version_match?("1.0.0-a.x", "< 1.0.0-a-b")
      assert matching(["1.0.0-a.x"], "< 1.0.0-a-b") == []
    end
  end

  defp version_match?(version, requirement) do
    case Version.parse(version) do
      {:ok, version} -> quietly(fn -> Version.match?(version, requirement) end)
      :error -> false
    end
  end

  defp matched_in_the_database(versions, requirement) do
    matched = MapSet.new(matching(versions, requirement))
    Enum.map(versions, &{&1, MapSet.member?(matched, &1)})
  end

  defp matching(versions, requirement) do
    query = quietly(fn -> VersionRequirement.where_matches(versions_query(versions), requirement) end)

    query
    |> exclude(:select)
    |> select([v], fragment("? ->> 'version'", v.firmware_metadata))
    |> Repo.all()
  end

  defp versions_query(versions) do
    from(v in fragment("SELECT jsonb_build_object('version', unnest(?::text[])) AS firmware_metadata", ^versions),
      select: v.firmware_metadata
    )
  end

  # `!=` is deprecated, and `Version` warns on every parse of one.
  defp quietly(fun) do
    {result, _warning} = with_io(:stderr, fun)
    result
  end
end

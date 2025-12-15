defmodule NervesHub.SemverMatchTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Repo

  describe "semver_match/2 database function" do
    test "pre-release version precedence" do
      # Example from semver.org:
      # 1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-alpha.beta < 1.0.0-beta < 1.0.0-beta.2 < 1.0.0-beta.11 < 1.0.0-rc.1 < 1.0.0
      assert query_semver_match("1.0.0-alpha", "< 1.0.0-alpha.1") == true
      assert query_semver_match("1.0.0-alpha.1", "< 1.0.0-alpha.beta") == true
      assert query_semver_match("1.0.0-alpha.beta", "< 1.0.0-beta") == true
      assert query_semver_match("1.0.0-beta", "< 1.0.0-beta.2") == true
      assert query_semver_match("1.0.0-beta.2", "< 1.0.0-beta.11") == true
      assert query_semver_match("1.0.0-beta.11", "< 1.0.0-rc.1") == true
      assert query_semver_match("1.0.0-rc.1", "< 1.0.0") == true

      # Numeric identifiers compared numerically
      assert query_semver_match("1.0.0-beta.2", "< 1.0.0-beta.11") == true
      assert query_semver_match("1.0.0-beta.11", "> 1.0.0-beta.2") == true

      # Larger set of fields has higher precedence
      assert query_semver_match("1.0.0-alpha", "< 1.0.0-alpha.1") == true
      assert query_semver_match("1.0.0-alpha.1", "> 1.0.0-alpha") == true
    end

    test "pre-release vs release versions" do
      # Pre-release version has lower precedence than release
      assert query_semver_match("1.0.0-alpha", "< 1.0.0") == true
      assert query_semver_match("1.0.0-rc.1", "< 1.0.0") == true
      assert query_semver_match("1.0.0", "> 1.0.0-alpha") == true

      # But pre-release is greater than previous release
      assert query_semver_match("1.0.0-alpha", "> 0.9.9") == true
      assert query_semver_match("2.0.0-beta", "> 1.9.9") == true
    end

    test "operators with pre-release versions" do
      # >= with pre-release
      assert query_semver_match("1.0.0-alpha", ">= 1.0.0-alpha") == true
      assert query_semver_match("1.0.0-beta", ">= 1.0.0-alpha") == true
      assert query_semver_match("1.0.0", ">= 1.0.0-alpha") == true
      assert query_semver_match("1.0.0-alpha", ">= 1.0.0-beta") == false

      # <= with pre-release
      assert query_semver_match("1.0.0-alpha", "<= 1.0.0-alpha") == true
      assert query_semver_match("1.0.0-alpha", "<= 1.0.0-beta") == true
      assert query_semver_match("1.0.0-alpha", "<= 1.0.0") == true
      assert query_semver_match("1.0.0-beta", "<= 1.0.0-alpha") == false

      # = with pre-release
      assert query_semver_match("1.0.0-alpha", "= 1.0.0-alpha") == true
      assert query_semver_match("1.0.0-beta", "= 1.0.0-alpha") == false
      assert query_semver_match("1.0.0", "= 1.0.0-alpha") == false
    end

    test "~> operator with pre-release versions" do
      # ~> operator only checks base version (ignores pre-release for filtering)
      # ~> 1.2 means >= 1.2.0 and < 2.0.0 (allows any 1.x version >= 1.2)
      assert query_semver_match("1.2.3-beta", "~> 1.2") == true
      assert query_semver_match("1.2.9-alpha", "~> 1.2") == true
      assert query_semver_match("1.3.0-rc1", "~> 1.2") == true
      assert query_semver_match("1.9.9-dev", "~> 1.2") == true
      assert query_semver_match("2.0.0-rc1", "~> 1.2") == false

      # ~> 1.2.0 means >= 1.2.0 and < 1.3.0 (more specific, only 1.2.x)
      assert query_semver_match("1.2.5-beta", "~> 1.2.0") == true
      assert query_semver_match("1.3.0-alpha", "~> 1.2.0") == false
    end

    test "~> tilde-arrow operator" do
      # ~> allows patch-level changes
      assert query_semver_match("1.2.0", "~> 1.2.0") == true
      assert query_semver_match("1.2.1", "~> 1.2.0") == true
      assert query_semver_match("1.2.99", "~> 1.2.0") == true

      # Should not match next minor version
      assert query_semver_match("1.3.0", "~> 1.2.0") == false
      assert query_semver_match("2.0.0", "~> 1.2.0") == false

      # Should not match lower versions
      assert query_semver_match("1.1.9", "~> 1.2.0") == false

      # Works with different precision (2 components)
      assert query_semver_match("2.0.0", "~> 2.0") == true
      assert query_semver_match("2.3.0", "~> 2.0") == true
      assert query_semver_match("2.9.99", "~> 2.0") == true
      assert query_semver_match("3.0.0", "~> 2.0") == false
      assert query_semver_match("1.9.9", "~> 2.0") == false

      # Single component
      assert query_semver_match("5.0.0", "~> 5") == true
      assert query_semver_match("5.9.99", "~> 5") == true
      assert query_semver_match("6.0.0", "~> 5") == false
      assert query_semver_match("4.9.9", "~> 5") == false
    end

    test ">= greater than or equal" do
      assert query_semver_match("1.0.0", ">= 1.0.0") == true
      assert query_semver_match("1.0.1", ">= 1.0.0") == true
      assert query_semver_match("1.1.0", ">= 1.0.0") == true
      assert query_semver_match("2.0.0", ">= 1.0.0") == true

      assert query_semver_match("0.9.9", ">= 1.0.0") == false
      assert query_semver_match("1.0.0", ">= 1.0.1") == false
    end

    test "<= less than or equal" do
      assert query_semver_match("1.0.0", "<= 1.0.0") == true
      assert query_semver_match("0.9.9", "<= 1.0.0") == true
      assert query_semver_match("0.1.0", "<= 1.0.0") == true

      assert query_semver_match("1.0.1", "<= 1.0.0") == false
      assert query_semver_match("1.1.0", "<= 1.0.0") == false
      assert query_semver_match("2.0.0", "<= 1.0.0") == false
    end

    test "> greater than" do
      assert query_semver_match("1.0.1", "> 1.0.0") == true
      assert query_semver_match("1.1.0", "> 1.0.0") == true
      assert query_semver_match("2.0.0", "> 1.0.0") == true

      assert query_semver_match("1.0.0", "> 1.0.0") == false
      assert query_semver_match("0.9.9", "> 1.0.0") == false
    end

    test "< less than" do
      assert query_semver_match("0.9.9", "< 1.0.0") == true
      assert query_semver_match("0.1.0", "< 1.0.0") == true

      assert query_semver_match("1.0.0", "< 1.0.0") == false
      assert query_semver_match("1.0.1", "< 1.0.0") == false
      assert query_semver_match("2.0.0", "< 1.0.0") == false
    end

    test "= equals (prefix match)" do
      # Equals should match if version starts with the requirement
      assert query_semver_match("1.0.0", "= 1.0.0") == true
      assert query_semver_match("1.0.5", "= 1.0") == true
      assert query_semver_match("1.2.3", "= 1") == true

      assert query_semver_match("2.0.0", "= 1.0.0") == false
      assert query_semver_match("1.1.0", "= 1.0") == false
    end

    test "null inputs return null" do
      assert query_semver_match(nil, ">= 1.0.0") == nil
      assert query_semver_match("1.0.0", nil) == nil
      assert query_semver_match(nil, nil) == nil
    end

    test "real-world scenarios" do
      # Common firmware update scenarios
      assert query_semver_match("1.2.3", "<= 1.5.0") == true
      assert query_semver_match("1.6.0", "<= 1.5.0") == false

      # Priority updates with version threshold
      assert query_semver_match("0.9.0", "<= 1.0.0") == true
      assert query_semver_match("1.0.0", "<= 1.0.0") == true
      assert query_semver_match("1.0.1", "<= 1.0.0") == false

      # Tilde-arrow for compatible versions
      assert query_semver_match("2.3.0", "~> 2.0") == true
      assert query_semver_match("2.3.5", "~> 2.0") == true
      assert query_semver_match("3.0.0", "~> 2.0") == false
    end
  end

  # Helper function to execute semver_match database function
  defp query_semver_match(version, requirement) do
    query = "SELECT semver_match($1, $2)"

    case Repo.query(query, [version, requirement]) do
      {:ok, %{rows: [[result]]}} -> result
      {:error, _} = error -> error
    end
  end
end

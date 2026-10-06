defmodule NervesHub.ManagedDeployments.VersionRequirement do
  @moduledoc """
  Matches devices' firmware versions against a deployment group's version
  requirement in the database.

  A deployment group's conditions hold an Elixir version requirement, such as
  `"~> 2.0"` or `">= 1.0.0 and < 2.0.0"`. Checking one with `Version.match?/2`
  means loading every candidate device's version into the BEAM, which for a
  large fleet is hundreds of thousands of rows on every count. This turns the
  requirement into comparisons on `semver_sort_key/1`, so Postgres does the
  filtering and only the result leaves the database.

  The translation follows `Version.match?/2` with its default `allow_pre: true`:

    * `==`, `!=`, `>`, `>=`, `<` and `<=` compare sort keys directly. Build
      metadata is ignored, as `Version` ignores it.
    * `~> 2.1.3` is `>= 2.1.3 and < 2.2.0-0`, and `~> 2.1` is
      `>= 2.1.0 and < 3.0.0-0`. `-0` is the lowest pre-release, so neither
      includes a pre-release of its upper bound, as `Version` doesn't.
    * `and` binds tighter than `or`.

  Devices report their own versions, so a device's version is first checked
  against SemVer's grammar. One that fails, or is missing, never matches, as
  `Version.parse/1` would refuse it. `semver_sort_key/1` alone is looser: it
  accepts leading zeros (`01.0.0`) and empty pre-release identifiers
  (`1.0.0-a..b`).

  ## Where this differs from `Version`

  `semver_sort_key/1` gives two orderings that `Version` doesn't. Both are
  accepted rather than worked around, because firmware versions don't take
  these shapes in practice:

    * **A number longer than 10 digits.** The key pads each number to 10 digits
      and truncates longer ones, so it can't order them. `Version` allows 14.
      A device version with such a number never matches here. A requirement
      with one (`>= 12345678901.0.0`) compares against the truncated number.
    * **A hyphen in a pre-release identifier.** `Version` orders `1.0.0-a.x`
      before `1.0.0-a-b`, comparing the identifier `a` with `a-b`. The key
      compares bytes, and `-` sorts before `.`, so it orders them the other
      way.

  `NervesHub.ManagedDeployments.VersionRequirementTest` checks the result
  against `Version.match?/2` across a range of versions and requirements, and
  pins both differences.
  """

  import Ecto.Query

  # SemVer 2.0.0's grammar, as `Version.parse/1` reads it, with numbers held to
  # the 10 digits `semver_sort_key/1` can order.
  @number "(0|[1-9][0-9]{0,9})"
  @pre_release_identifier "(0|[1-9][0-9]{0,9}|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
  @valid_version "^#{@number}\\.#{@number}\\.#{@number}" <>
                   "(-#{@pre_release_identifier}(\\.#{@pre_release_identifier})*)?" <>
                   "(\\+[0-9A-Za-z-]+(\\.[0-9A-Za-z-]+)*)?$"

  # Checked in this order, as `Version`'s own lexer does, so that `>=` is not
  # read as `>` followed by `=`.
  @operators [
    {">=", :>=},
    {"<=", :<=},
    {"~>", :~>},
    {">", :>},
    {"<", :<},
    {"==", :==},
    {"!=", :!=},
    {"!", :!=}
  ]

  @doc """
  Filters a device query to devices whose firmware version satisfies
  `requirement`.

  The query's first binding must have a `firmware_metadata` map holding a
  `"version"`. Raises `Version.InvalidRequirementError` if `requirement` is not
  a valid Elixir version requirement. Deployment group conditions are validated
  when saved, so one read from the database always is.
  """
  @spec where_matches(Ecto.Queryable.t(), String.t()) :: Ecto.Query.t()
  def where_matches(query, requirement) do
    _ = Version.parse_requirement!(requirement)

    matches =
      requirement
      |> String.split(" or ")
      |> Enum.map(fn alternative ->
        alternative
        |> String.split(" and ")
        |> Enum.map(&clause/1)
        |> Enum.reduce(fn clause, acc -> dynamic(^acc and ^clause) end)
      end)
      |> Enum.reduce(fn alternative, acc -> dynamic(^acc or ^alternative) end)

    valid = dynamic([d], fragment("(? ->> 'version') ~ ?", d.firmware_metadata, ^@valid_version))

    where(query, ^dynamic(^valid and ^matches))
  end

  defp clause(clause) do
    case split_operator(String.trim(clause)) do
      {:~>, operand} ->
        {lower, upper} = approximate_bounds(operand)
        dynamic(^compare(:>=, lower) and ^compare(:<, upper))

      {operator, operand} ->
        compare(operator, operand)
    end
  end

  # A clause with no operator means `==`, as it does to `Version`.
  defp split_operator(clause) do
    Enum.find_value(@operators, {:==, clause}, fn {prefix, operator} ->
      if String.starts_with?(clause, prefix) do
        {operator, clause |> String.replace_prefix(prefix, "") |> String.trim_leading()}
      end
    end)
  end

  # `~>` alone may leave out the patch version, as in "~> 2.1" or "~> 2.1-dev".
  defp approximate_bounds(operand) do
    case Version.parse(operand) do
      {:ok, version} ->
        {to_string(%{version | build: nil}), "#{version.major}.#{version.minor + 1}.0-0"}

      :error ->
        [base | pre] =
          operand
          |> String.split("+", parts: 2)
          |> hd()
          |> String.split("-", parts: 2)

        version = Version.parse!(Enum.join([base <> ".0" | pre], "-"))

        {to_string(version), "#{version.major + 1}.0.0-0"}
    end
  end

  # The bound is wrapped in a scalar subquery so Postgres works out its key
  # once for the query, rather than once per device.
  defp compare(:==, version) do
    dynamic(
      [d],
      fragment(
        ~s|semver_sort_key(? ->> 'version') COLLATE "C" = (SELECT semver_sort_key(?)) COLLATE "C"|,
        d.firmware_metadata,
        ^version
      )
    )
  end

  defp compare(:!=, version) do
    dynamic(
      [d],
      fragment(
        ~s|semver_sort_key(? ->> 'version') COLLATE "C" <> (SELECT semver_sort_key(?)) COLLATE "C"|,
        d.firmware_metadata,
        ^version
      )
    )
  end

  defp compare(:>, version) do
    dynamic(
      [d],
      fragment(
        ~s|semver_sort_key(? ->> 'version') COLLATE "C" > (SELECT semver_sort_key(?)) COLLATE "C"|,
        d.firmware_metadata,
        ^version
      )
    )
  end

  defp compare(:>=, version) do
    dynamic(
      [d],
      fragment(
        ~s|semver_sort_key(? ->> 'version') COLLATE "C" >= (SELECT semver_sort_key(?)) COLLATE "C"|,
        d.firmware_metadata,
        ^version
      )
    )
  end

  defp compare(:<, version) do
    dynamic(
      [d],
      fragment(
        ~s|semver_sort_key(? ->> 'version') COLLATE "C" < (SELECT semver_sort_key(?)) COLLATE "C"|,
        d.firmware_metadata,
        ^version
      )
    )
  end

  defp compare(:<=, version) do
    dynamic(
      [d],
      fragment(
        ~s|semver_sort_key(? ->> 'version') COLLATE "C" <= (SELECT semver_sort_key(?)) COLLATE "C"|,
        d.firmware_metadata,
        ^version
      )
    )
  end
end

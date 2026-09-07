defmodule NervesHub.ErrorReports.Fingerprint do
  @moduledoc """
  Decides which occurrences are the same bug.

  Two crashes of one bug differ by a pid, a timeout and a line of formatting.
  Grouping them means deciding which of those differences are noise, and that
  decision is what the product page is built on: too coarse and unrelated
  crashes merge, too fine and one bug becomes a thousand issues.

      sha256(version <> kind <> normalize(reason) <> top three frames)

  ## Why on the server

  One rule, in one place, revisable without a firmware release. Grouping is the
  part of this feature most likely to need adjusting once real fleets report
  real errors, and adjusting it should not mean waiting for devices to update.

  `version/0` is what makes revising it safe. Bump it and new occurrences group
  into new issues rather than silently re-grouping history against a rule that
  did not produce it. A revision is **not** retroactive: history splits at the
  version boundary, and that is the intended behaviour rather than a limitation
  to work around.

  ## What is deliberately ignored

  **Line numbers.** A line moves whenever the file above it changes, and an
  issue that splits on every unrelated edit is worse than no grouping at all.
  Frames contribute their module and function only.

  **Frames past the third.** The innermost frames say what broke; the rest say
  how it was reached, which varies between callers of the same broken code.

  **Numbers of two digits or more**, along with pids, refs, ports, hex
  addresses and UUIDs. All of these are per-occurrence data. Single digits are
  kept, so `Foo.bar/2` and `Foo.bar/3` stay apart.

  The known cost of that last rule: two errors differing only by a numeric code
  — `ERROR 23505` and `ERROR 23503` — group together. A report that knows
  better can supply its own key; see `for_report/1`.
  """

  @fingerprint_version 1

  # Ordered, and the order matters: UUIDs and pids contain digits, so they are
  # collapsed before the digit rule would chew them into something unreadable.
  @substitutions [
    {~r/\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b/, "UUID"},
    {~r/#PID<[^>]*>/, "#PID<>"},
    {~r/#Reference<[^>]*>/, "#Reference<>"},
    {~r/#Port<[^>]*>/, "#Port<>"},
    {~r/0x[0-9a-fA-F]+/, "0x"},
    {~r/\d{2,}/, "N"}
  ]

  @frames_used 3
  @hash_length 32

  @doc "The revision of the algorithm below."
  def version(), do: @fingerprint_version

  @doc """
  The fingerprint for one validated report.

  A `:fingerprint` supplied by the device wins. That is what lets application
  code group by something the stacktrace cannot know — every failure in a
  payment integration arriving through one HTTP client function is one issue to
  the person on call, and six to a stacktrace.

  A supplied key is hashed under its own domain separator, so it produces a
  value of the same shape as a computed one and cannot collide with one.
  """
  @spec for_report(map()) :: String.t()
  def for_report(%{fingerprint: supplied}) when is_binary(supplied) and supplied != "" do
    hash(["custom", 0, supplied])
  end

  def for_report(attrs), do: compute(attrs)

  @doc """
  The fingerprint derived from a report's own content.

  ## Examples

      iex> alias NervesHub.ErrorReports.Fingerprint
      iex> a = Fingerprint.compute(%{kind: "error", reason: "timeout after 5000ms in #PID<0.412.0>", frames: []})
      iex> b = Fingerprint.compute(%{kind: "error", reason: "timeout after 9000ms in #PID<0.918.0>", frames: []})
      iex> a == b
      true

  """
  @spec compute(map()) :: String.t()
  def compute(attrs) do
    kind = Map.get(attrs, :kind) || ""
    reason = Map.get(attrs, :reason) || ""
    frames = Map.get(attrs, :frames) || []

    hash(["auto", @fingerprint_version, kind, normalize_reason(reason)] ++ frame_keys(frames))
  end

  @doc """
  Strips the per-occurrence detail out of a reason.

  ## Examples

      iex> alias NervesHub.ErrorReports.Fingerprint
      iex> Fingerprint.normalize_reason("GenServer #PID<0.412.0> terminating")
      "GenServer #PID<> terminating"

      iex> alias NervesHub.ErrorReports.Fingerprint
      iex> Fingerprint.normalize_reason("no function clause matching in Foo.bar/2")
      "no function clause matching in Foo.bar/2"

      iex> alias NervesHub.ErrorReports.Fingerprint
      iex> Fingerprint.normalize_reason("could not fetch device 41827 at 0x7f3ab2")
      "could not fetch device N at 0x"

      iex> alias NervesHub.ErrorReports.Fingerprint
      iex> Fingerprint.normalize_reason("firmware 550e8400-e29b-41d4-a716-446655440000 is missing")
      "firmware UUID is missing"

  """
  @spec normalize_reason(String.t()) :: String.t()
  def normalize_reason(reason) when is_binary(reason) do
    Enum.reduce(@substitutions, reason, fn {pattern, replacement}, acc ->
      String.replace(acc, pattern, replacement)
    end)
  end

  def normalize_reason(_reason), do: ""

  # Module and function, never the file or the line. A frame carrying neither
  # still contributes a slot, so a stacktrace of anonymous frames does not
  # silently collapse onto one that has none at all.
  defp frame_keys(frames) do
    frames
    |> Enum.take(@frames_used)
    |> Enum.flat_map(fn frame ->
      [Map.get(frame, :module) || "", Map.get(frame, :function) || ""]
    end)
  end

  # A domain separator between every part, so that two different splits of the
  # same characters cannot hash alike -- kind "ab" with reason "c" must not
  # match kind "a" with reason "bc".
  defp hash(parts) do
    parts
    |> Enum.map_join("\0", &to_string/1)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, @hash_length)
  end
end

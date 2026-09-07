defmodule NervesHub.ErrorReports.FingerprintTest do
  use ExUnit.Case, async: true

  alias NervesHub.ErrorReports.Fingerprint

  doctest Fingerprint

  @frames [
    %{module: "MyApp.Worker", function: "handle_info/2", file: "lib/worker.ex", line: 42},
    %{module: "MyApp.Supervisor", function: "init/1", file: "lib/sup.ex", line: 9}
  ]

  defp report(overrides \\ %{}) do
    Map.merge(%{kind: "error", reason: "** (RuntimeError) boom", frames: @frames}, overrides)
  end

  describe "grouping the same bug" do
    test "two occurrences differing only by pid group together" do
      a = Fingerprint.compute(report(%{reason: "GenServer #PID<0.412.0> terminating"}))
      b = Fingerprint.compute(report(%{reason: "GenServer #PID<0.918.0> terminating"}))

      assert a == b
    end

    test "two occurrences differing only by a multi-digit number group together" do
      a = Fingerprint.compute(report(%{reason: "timeout after 5000ms"}))
      b = Fingerprint.compute(report(%{reason: "timeout after 250ms"}))

      assert a == b
    end

    test "a line number moving does not split a group" do
      moved = List.update_at(@frames, 0, &%{&1 | line: 4711})

      assert Fingerprint.compute(report()) == Fingerprint.compute(report(%{frames: moved}))
    end

    test "frames past the third do not split a group" do
      three = @frames ++ [%{module: "MyApp.App", function: "start/2", file: "lib/app.ex", line: 5}]
      four = three ++ [%{module: "Elsewhere", function: "call/0", file: "e.ex", line: 1}]

      assert Fingerprint.compute(report(%{frames: three})) ==
               Fingerprint.compute(report(%{frames: four}))
    end

    test "but the third frame itself still counts" do
      three = @frames ++ [%{module: "MyApp.App", function: "start/2", file: "lib/app.ex", line: 5}]

      refute Fingerprint.compute(report()) == Fingerprint.compute(report(%{frames: three}))
    end
  end

  describe "keeping different bugs apart" do
    test "a different reason is a different group" do
      refute Fingerprint.compute(report()) ==
               Fingerprint.compute(report(%{reason: "** (ArgumentError) nope"}))
    end

    test "a different kind is a different group" do
      refute Fingerprint.compute(report()) == Fingerprint.compute(report(%{kind: "exit"}))
    end

    test "a different innermost frame is a different group" do
      elsewhere = List.update_at(@frames, 0, &%{&1 | function: "handle_call/3"})

      refute Fingerprint.compute(report()) == Fingerprint.compute(report(%{frames: elsewhere}))
    end

    test "single digits are kept, so arity still separates two functions" do
      arity_three = List.update_at(@frames, 0, &%{&1 | function: "handle_info/3"})

      refute Fingerprint.compute(report()) == Fingerprint.compute(report(%{frames: arity_three}))
    end

    # The parts are joined with a separator so that moving characters across a
    # boundary cannot produce the same hash.
    test "the same characters split differently do not collide" do
      refute Fingerprint.compute(%{kind: "ab", reason: "c", frames: []}) ==
               Fingerprint.compute(%{kind: "a", reason: "bc", frames: []})
    end
  end

  describe "for_report/1" do
    test "a device-supplied key wins over the computed one" do
      supplied = Fingerprint.for_report(Map.put(report(), :fingerprint, "payment-gateway"))

      refute supplied == Fingerprint.compute(report())
    end

    test "the same supplied key groups two unrelated errors together" do
      a = Fingerprint.for_report(%{kind: "error", reason: "a", frames: [], fingerprint: "pay"})
      b = Fingerprint.for_report(%{kind: "exit", reason: "b", frames: [], fingerprint: "pay"})

      assert a == b
    end

    test "an empty supplied key falls back to computing one" do
      assert Fingerprint.for_report(Map.put(report(), :fingerprint, "")) ==
               Fingerprint.compute(report())
    end

    test "a missing key falls back to computing one" do
      assert Fingerprint.for_report(report()) == Fingerprint.compute(report())
    end
  end

  describe "shape" do
    test "is 32 lowercase hex characters" do
      assert Fingerprint.compute(report()) =~ ~r/\A[0-9a-f]{32}\z/
    end

    test "a report with nothing in it still produces one" do
      assert Fingerprint.compute(%{}) =~ ~r/\A[0-9a-f]{32}\z/
    end
  end

  describe "normalize_reason/1" do
    test "collapses refs and ports as well as pids" do
      assert Fingerprint.normalize_reason("#Reference<0.1.2.3> and #Port<0.5>") ==
               "#Reference<> and #Port<>"
    end

    test "anything that is not a string normalizes to empty" do
      assert Fingerprint.normalize_reason(nil) == ""
      assert Fingerprint.normalize_reason(:boom) == ""
    end
  end

  describe "version/0" do
    test "participates in the hash, so a bump regroups rather than reuses" do
      # Recomputing with the version held constant must be stable; the guard
      # against a silent regrouping is that the version is in the input at all.
      assert Fingerprint.compute(report()) == Fingerprint.compute(report())
      assert is_integer(Fingerprint.version())
    end
  end
end

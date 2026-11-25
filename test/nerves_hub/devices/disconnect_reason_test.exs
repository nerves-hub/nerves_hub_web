defmodule NervesHub.Devices.DisconnectReasonTest do
  use ExUnit.Case, async: true

  alias NervesHub.Devices.DisconnectReason

  describe "load/1" do
    test "loads every reason it dumps" do
      for reason <- DisconnectReason.values() do
        assert {:ok, dumped} = DisconnectReason.dump(reason)
        assert {:ok, ^reason} = DisconnectReason.load(dumped)
      end
    end

    # Releases before the enum wrote this, and rows written by them stay.
    test "loads the label releases before the enum wrote" do
      assert {:ok, :stale_connection} = DisconnectReason.load("Stale connection")
    end

    # During a rolling deploy the previous release can write a value this one
    # does not list. Raising would take down every page that reads the row.
    test "loads an unknown value as nil rather than raising" do
      assert {:ok, nil} = DisconnectReason.load("a reason from the future")
    end
  end

  describe "cast/1" do
    test "accepts a reason as an atom or a string" do
      assert {:ok, :deep_sleep} = DisconnectReason.cast(:deep_sleep)
      assert {:ok, :deep_sleep} = DisconnectReason.cast("deep_sleep")
    end

    test "refuses anything else" do
      assert :error = DisconnectReason.cast("Stale connection")
      assert :error = DisconnectReason.cast(:asleep)
      assert :error = DisconnectReason.cast(42)
    end
  end

  test "dump/1 refuses an unknown reason" do
    assert :error = DisconnectReason.dump(:asleep)
  end

  test "sleep is planned, a stale connection is not" do
    for reason <- DisconnectReason.sleep_values() do
      assert DisconnectReason.sleep?(reason)
      assert reason in DisconnectReason.planned_values()
    end

    refute DisconnectReason.sleep?(:rebooting)
    refute :stale_connection in DisconnectReason.planned_values()
    refute :duplicate_connection in DisconnectReason.planned_values()
  end

  test "every reason has a label, and a stale connection keeps the one webhooks sent" do
    for reason <- DisconnectReason.values() do
      assert is_binary(DisconnectReason.label(reason))
    end

    assert DisconnectReason.label(:stale_connection) == "Stale connection"
    assert DisconnectReason.label(nil) == nil
  end
end

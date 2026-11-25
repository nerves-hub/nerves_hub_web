defmodule NervesHub.Devices.DeviceConnectionSleepTest do
  use ExUnit.Case, async: true

  alias NervesHub.Devices.DeviceConnection

  @slept_at ~U[2026-11-15 10:00:00.000000Z]

  defp asleep(attrs) do
    struct!(
      %DeviceConnection{
        status: :disconnected,
        disconnected_reason: :deep_sleep,
        disconnected_at: @slept_at,
        expected_wake_at: DateTime.add(@slept_at, 5, :minute)
      },
      attrs
    )
  end

  describe "sleep_state/2" do
    test "nil for a connection that did not end in sleep" do
      assert DeviceConnection.sleep_state(nil, @slept_at) == nil
      assert DeviceConnection.sleep_state(asleep(disconnected_reason: nil), @slept_at) == nil
      assert DeviceConnection.sleep_state(asleep(disconnected_reason: :rebooting), @slept_at) == nil
    end

    test "going to sleep while the connection is still open" do
      connection = asleep(status: :connected, disconnected_at: nil)

      assert DeviceConnection.sleep_state(connection, @slept_at) == :going_to_sleep
    end

    test "asleep until the deadline, overdue after it" do
      connection = asleep(%{})

      assert DeviceConnection.sleep_state(connection, DateTime.add(@slept_at, 1, :minute)) == :asleep
      # Due at 5 minutes, but within the two-minute floor of the margin.
      assert DeviceConnection.sleep_state(connection, DateTime.add(@slept_at, 6, :minute)) == :asleep
      assert DeviceConnection.sleep_state(connection, DateTime.add(@slept_at, 8, :minute)) == :overdue
    end

    test "light sleep counts as sleep" do
      connection = asleep(disconnected_reason: :light_sleep)

      assert DeviceConnection.sleep_state(connection, @slept_at) == :asleep
    end

    test "a device that gave no time is never overdue" do
      connection = asleep(expected_wake_at: nil)

      assert DeviceConnection.sleep_state(connection, DateTime.add(@slept_at, 30, :day)) == :asleep
    end
  end

  describe "wake_deadline/1" do
    test "a short sleep gets the two-minute floor" do
      assert DeviceConnection.wake_deadline(asleep(%{})) == DateTime.add(@slept_at, 7, :minute)
    end

    # An RC slow clock drifts by several percent, so a long sleeper is allowed
    # a share of its sleep rather than a fixed few minutes.
    test "a long sleep gets a tenth of its length" do
      connection = asleep(expected_wake_at: DateTime.add(@slept_at, 10, :hour))

      assert DeviceConnection.wake_deadline(connection) == DateTime.add(@slept_at, 11, :hour)
    end

    test "nil when the device gave no time" do
      assert DeviceConnection.wake_deadline(asleep(expected_wake_at: nil)) == nil
    end
  end
end

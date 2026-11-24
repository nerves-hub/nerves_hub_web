defmodule NervesHubWeb.Components.DevicePage.ComponentReadingsTest do
  use ExUnit.Case, async: true

  alias NervesHubWeb.Components.DevicePage.ComponentReadings

  test "writes a value to as many places as tell it apart" do
    assert ComponentReadings.value(1240) == "1,240"
    assert ComponentReadings.value(1240.4) == "1,240"
    assert ComponentReadings.value(21.43) == "21.4"
    assert ComponentReadings.value(-18.4) == "-18.4"
    assert ComponentReadings.value(48.0) == "48"
    assert ComponentReadings.value(0.31) == "0.31"
    assert ComponentReadings.value(5.0) == "5"
  end

  test "names readings by convention, and others as sent" do
    assert ComponentReadings.label("co2") == "CO₂"
    assert ComponentReadings.label("door_contact") == "Door contact"
    assert ComponentReadings.unit("temperature") == "°C"
    assert ComponentReadings.unit("door_contact") == nil
  end

  test "a short span" do
    assert ComponentReadings.span(30) == "<1 m"
    assert ComponentReadings.span(26 * 60) == "26 m"
    assert ComponentReadings.span(86 * 60) == "1 h 26 m"
    assert ComponentReadings.span(3 * 3600) == "3 h"
    assert ComponentReadings.span(2 * 86_400 + 4 * 3600) == "2 d 4 h"
  end

  describe "segments/1" do
    @from ~U[2026-11-23 12:00:00Z]
    @now ~U[2026-11-24 12:00:00Z]

    test "starts from the value before the window and cuts at each change" do
      history = %{
        before: "locked",
        changes: [%{at: ~U[2026-11-24 00:00:00Z], value: "unlocked", detail: ""}]
      }

      assert ComponentReadings.segments(%{
               history: history,
               value: "unlocked",
               since: ~U[2026-11-24 00:00:00Z],
               from: @from,
               now: @now
             }) == [%{value: "locked", seconds: 12 * 3600}, %{value: "unlocked", seconds: 12 * 3600}]
    end

    test "with no history, the current value set before the window fills it" do
      assert ComponentReadings.segments(%{
               history: nil,
               value: "locked",
               since: ~U[2026-11-20 00:00:00Z],
               from: @from,
               now: @now
             }) == [%{value: "locked", seconds: 24 * 3600}]
    end

    test "with no history, a value set in the window leaves a gap before it" do
      assert ComponentReadings.segments(%{
               history: %{before: nil, changes: []},
               value: "locked",
               since: ~U[2026-11-24 06:00:00Z],
               from: @from,
               now: @now
             }) == [%{value: nil, seconds: 18 * 3600}, %{value: "locked", seconds: 6 * 3600}]
    end
  end
end

defmodule NervesHub.Devices.ConnectionTimelineTest do
  use ExUnit.Case, async: true

  alias NervesHub.Devices.ConnectionTimeline

  @from ~U[2026-11-12 08:00:00Z]
  @until ~U[2026-11-12 11:00:00Z]

  defp at(minutes), do: DateTime.add(@from, minutes, :minute)

  defp connection(established_at, disconnected_at, extra \\ %{}) do
    Map.merge(
      %{established_at: established_at, disconnected_at: disconnected_at, reason: "", interface: "", ip_address: ""},
      extra
    )
  end

  describe "build/4" do
    test "is offline for the whole span when the device had no connection in it" do
      assert %ConnectionTimeline{offline: [offline], reconnects: []} = ConnectionTimeline.build([], nil, @from, @until)

      assert offline == %{from: @from, until: nil, reason: nil, interface: nil, ip_address: nil}
    end

    test "is the time between connections, with why the first ended and where the device came back" do
      connections = [
        connection(at(-30), at(60), %{reason: "Stale connection"}),
        connection(at(74), nil, %{interface: "wifi", ip_address: "10.0.4.17"})
      ]

      assert %ConnectionTimeline{offline: [offline], reconnects: []} =
               ConnectionTimeline.build(connections, nil, @from, @until)

      assert offline == %{
               from: at(60),
               until: at(74),
               reason: "Stale connection",
               interface: "wifi",
               ip_address: "10.0.4.17"
             }
    end

    test "starts time offline at the start of the span where the connection before it really ended" do
      previous = connection(at(-90), at(-20), %{reason: "Reconnected"})

      assert %ConnectionTimeline{offline: [offline]} =
               ConnectionTimeline.build([connection(at(15), nil)], previous, @from, @until)

      assert %{from: from, until: until, reason: "Reconnected"} = offline
      assert from == at(-20)
      assert until == at(15)
    end

    test "leaves time offline open while the device hasn't come back" do
      assert %ConnectionTimeline{offline: [offline]} =
               ConnectionTimeline.build([connection(at(-10), at(150))], nil, @from, @until)

      assert %{from: from, until: nil, reason: nil} = offline
      assert from == at(150)
    end

    test "marks a reconnect under a minute, or over a connection still open, rather than time offline" do
      quick = DateTime.add(at(60), 30, :second)

      connections = [
        connection(at(-10), at(60)),
        connection(quick, at(120)),
        connection(at(100), nil)
      ]

      assert ConnectionTimeline.build(connections, nil, @from, @until) ==
               %ConnectionTimeline{offline: [], reconnects: [quick, at(100)]}
    end

    test "leaves out what happened before the span" do
      connections = [connection(at(-60), at(-40)), connection(at(-20), at(-19)), connection(at(-18), nil)]

      assert ConnectionTimeline.build(connections, nil, @from, @until) == %ConnectionTimeline{
               offline: [],
               reconnects: []
             }
    end

    test "merges connections that overlap, whatever order they come in" do
      connections = [connection(at(50), at(180)), connection(at(-10), at(70)), connection(at(20), at(40))]

      assert %ConnectionTimeline{offline: []} = ConnectionTimeline.build(connections, nil, @from, @until)
    end
  end

  describe "offline_periods/3" do
    test "cuts each time offline to the span, as unix milliseconds" do
      timeline = %ConnectionTimeline{
        offline: [
          %{from: at(-20), until: at(15), reason: nil, interface: nil, ip_address: nil},
          %{from: at(150), until: nil, reason: nil, interface: nil, ip_address: nil}
        ]
      }

      assert ConnectionTimeline.offline_periods(timeline, @from, @until) == [
               [DateTime.to_unix(@from, :millisecond), DateTime.to_unix(at(15), :millisecond)],
               [DateTime.to_unix(at(150), :millisecond), DateTime.to_unix(@until, :millisecond)]
             ]
    end
  end

  describe "summary/3" do
    test "is the share online, the disconnects that began in the span and its reconnects" do
      timeline = %ConnectionTimeline{
        offline: [
          %{from: at(-20), until: at(15), reason: nil, interface: nil, ip_address: nil},
          %{from: at(100), until: at(115), reason: nil, interface: nil, ip_address: nil}
        ],
        reconnects: [at(130), at(200)]
      }

      assert ConnectionTimeline.summary(timeline, @from, @until) == %{
               online_percent: 83,
               disconnects: 1,
               reconnects: 1
             }
    end

    test "only says 100% online when the device was never offline" do
      timeline = %ConnectionTimeline{
        offline: [%{from: at(0), until: DateTime.add(at(0), 61, :second), reason: nil, interface: nil, ip_address: nil}]
      }

      assert %{online_percent: 99} = ConnectionTimeline.summary(timeline, @from, @until)
      assert %{online_percent: 100} = ConnectionTimeline.summary(%ConnectionTimeline{}, @from, @until)
    end
  end
end

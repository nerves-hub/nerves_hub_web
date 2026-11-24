defmodule NervesHub.Devices.ComponentsTest do
  @moduledoc """
  Reading a components snapshot, and storing it as changes.

  The rules here are the ones docs/components.md publishes to client authors,
  so a change that breaks one of these breaks a client.
  """

  use NervesHub.DataCase, async: false

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Components
  alias NervesHub.Devices.DeviceComponent
  alias NervesHub.Devices.DeviceComponentHistory
  alias NervesHub.Devices.DeviceComponentReading
  alias NervesHub.Extensions.PubSub
  alias NervesHub.Fixtures
  alias Phoenix.Socket.Broadcast

  @now ~U[2026-11-24 12:00:00.000000Z]

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    device_info = %DeviceInfo{
      device_id: device.id,
      device_identifier: device.identifier,
      org_id: device.org_id,
      product_id: device.product_id
    }

    AnalyticsRepo.query!("TRUNCATE TABLE device_component_history")
    AnalyticsRepo.query!("TRUNCATE TABLE device_component_readings")

    on_exit(fn ->
      AnalyticsRepo.query!("TRUNCATE TABLE device_component_history")
      AnalyticsRepo.query!("TRUNCATE TABLE device_component_readings")
    end)

    %{device: device, product: product, device_info: device_info, org: org, firmware: firmware}
  end

  defp probe(overrides \\ %{}) do
    Map.merge(
      %{
        "namespace" => "zigbee",
        "vendor" => "1286",
        "model" => "SNZB-02D",
        "serial" => "00:12:4b:00:2a:3f:91:c7",
        "name" => "Freezer probe A",
        "vendor_name" => "Sonoff",
        "firmware_version" => "2.1.0"
      },
      overrides
    )
  end

  defp sync(device_info, components, at \\ @now) do
    {:ok, entries} = Components.parse(components, at)
    :ok = Components.sync_snapshot(device_info, entries, at)
  end

  defp history(device) do
    :ok = Buffer.flush(DeviceComponentHistory)

    DeviceComponentHistory
    |> where(device_id: ^device.id)
    |> order_by(asc: :timestamp)
    |> AnalyticsRepo.all()
    |> Enum.map(&{&1.event, &1.detail})
  end

  describe "parse/2" do
    test "reads the required and optional fields, and ignores others" do
      assert {:ok, [entry]} = Components.parse([probe(%{"colour" => "blue"})], @now)

      assert entry.namespace == "zigbee"
      assert entry.vendor == "1286"
      assert entry.model == "SNZB-02D"
      assert entry.name == "Freezer probe A"
      assert entry.model_name == nil
      assert entry.reachable
      refute Map.has_key?(entry, :colour)
    end

    test "rejects the whole snapshot for one bad entry" do
      assert Components.parse([probe(), %{"namespace" => "zigbee"}], @now) == {:error, :malformed_entry}
      assert Components.parse([probe(%{"serial" => 42})], @now) == {:error, :malformed_entry}
      assert Components.parse([probe(%{"reachable" => "no"})], @now) == {:error, :malformed_entry}
      assert Components.parse(["zigbee"], @now) == {:error, :malformed_entry}
    end

    test "an empty optional string counts as left out, and an empty required one is rejected" do
      assert {:ok, [entry]} = Components.parse([probe(%{"firmware_version" => "", "address" => ""})], @now)
      assert entry.firmware_version == nil
      assert entry.address == nil

      assert Components.parse([probe(%{"serial" => ""})], @now) == {:error, :malformed_entry}
    end

    test "rejects anything that isn't a list" do
      assert Components.parse(%{}, @now) == {:error, :not_a_list}
    end

    test "rejects a namespace that breaks the rule" do
      assert Components.parse([probe(%{"namespace" => "Zigbee"})], @now) == {:error, :bad_namespace}
      assert Components.parse([probe(%{"namespace" => "1wire"})], @now) == {:error, :bad_namespace}
      assert {:ok, _} = Components.parse([probe(%{"namespace" => "one_wire"})], @now)
    end

    test "rejects a string over 255 characters" do
      assert Components.parse([probe(%{"name" => String.duplicate("a", 256)})], @now) == {:error, :too_long}
    end

    test "rejects two entries with the same namespace and serial" do
      assert Components.parse([probe(), probe(%{"name" => "Copy"})], @now) == {:error, :duplicate}
      assert {:ok, [_, _]} = Components.parse([probe(), probe(%{"namespace" => "custom"})], @now)
    end

    test "rejects more than 500 entries" do
      components = for n <- 1..501, do: probe(%{"serial" => "s#{n}"})

      assert Components.parse(components, @now) == {:error, :too_many}
    end

    test "believes a last_seen_at only within the window" do
      seen = fn at ->
        {:ok, [entry]} = Components.parse([probe(%{"last_seen_at" => at})], @now)
        entry.last_seen_at
      end

      assert seen.("2026-11-24T10:42:11Z") == ~U[2026-11-24 10:42:11Z]
      assert seen.("1970-01-01T00:00:00Z") == nil
      assert seen.("2026-11-24T14:00:00Z") == nil
      assert seen.("yesterday") == nil
    end
  end

  describe "sync_snapshot/3" do
    test "stores a new component as working, and records it appearing", %{device: device, device_info: info} do
      sync(info, [probe()])

      assert [component] = Components.list_for_device(device)
      assert DeviceComponent.status(component) == :working
      assert component.first_seen_at == @now
      assert component.missing_since == nil
      assert history(device) == [{"appeared", ""}]
    end

    test "an unchanged snapshot writes nothing and records nothing", %{device: device, device_info: info} do
      sync(info, [probe()])
      [before] = Components.list_for_device(device)

      sync(info, [probe()], DateTime.add(@now, 60))

      assert [after_] = Components.list_for_device(device)
      assert after_.updated_at == before.updated_at
      assert history(device) == [{"appeared", ""}]
    end

    test "an unreachable component is missing, and comes back", %{device: device, device_info: info} do
      sync(info, [probe()])
      sync(info, [probe(%{"reachable" => false})], DateTime.add(@now, 60))

      [component] = Components.list_for_device(device)
      assert DeviceComponent.missing_reason(component) == :unreachable
      assert component.missing_since == DateTime.add(@now, 60)

      sync(info, [probe()], DateTime.add(@now, 120))

      [component] = Components.list_for_device(device)
      assert DeviceComponent.status(component) == :working
      assert component.missing_since == nil
      assert history(device) == [{"appeared", ""}, {"missing", "unreachable"}, {"returned", ""}]
    end

    test "a component left out is kept, as unlisted", %{device: device, device_info: info} do
      lock = probe(%{"namespace" => "zwave", "serial" => "e3a177c2:9", "name" => "Office lock"})
      sync(info, [probe(), lock])
      sync(info, [lock], DateTime.add(@now, 60))

      probe = Enum.find(Components.list_for_device(device), &(&1.namespace == "zigbee"))
      assert DeviceComponent.missing_reason(probe) == :unlisted
      assert probe.missing_since == DateTime.add(@now, 60)
      assert {"missing", "unlisted"} in history(device)
    end

    test "keeps at most 1,000 components, forgetting those missing longest", %{device: device, device_info: info} do
      batch = fn prefix -> for i <- 1..500, do: probe(%{"serial" => "#{prefix}-#{i}"}) end

      sync(info, batch.("a"))
      sync(info, batch.("b"), DateTime.add(@now, 60))
      sync(info, batch.("c"), DateTime.add(@now, 120))

      serials = Enum.map(Components.list_for_device(device), & &1.serial)
      assert length(serials) == 1000
      refute Enum.any?(serials, &String.starts_with?(&1, "a-"))
      assert Enum.count(history(device), &(&1 == {"forgotten", ""})) == 500
    end

    test "an empty snapshot marks every component unlisted", %{device: device, device_info: info} do
      sync(info, [probe()])
      sync(info, [], DateTime.add(@now, 60))

      assert [%{listed: false}] = Components.list_for_device(device)
    end

    test "being left out again doesn't move when it went missing", %{device: device, device_info: info} do
      sync(info, [probe(%{"reachable" => false})])
      sync(info, [], DateTime.add(@now, 60))

      assert [%{missing_since: @now}] = Components.list_for_device(device)
      assert history(device) == [{"appeared", ""}, {"missing", "unreachable"}]
    end

    test "a firmware change is recorded with the version it moved from", %{device: device, device_info: info} do
      sync(info, [probe()])
      sync(info, [probe(%{"firmware_version" => "2.2.0"})], DateTime.add(@now, 60))

      assert [%{firmware_version: "2.2.0"}] = Components.list_for_device(device)
      assert history(device) == [{"appeared", ""}, {"firmware_changed", "2.1.0"}]
    end

    test "keeps the last believable last_seen_at", %{device: device, device_info: info} do
      sync(info, [probe(%{"last_seen_at" => "2026-11-24T11:59:00Z"})])
      sync(info, [probe(%{"reachable" => false})], DateTime.add(@now, 60))

      assert [%{last_seen_at: ~U[2026-11-24 11:59:00.000000Z]}] = Components.list_for_device(device)
    end

    test "tells an open device page only when something changed", %{device: device, device_info: info} do
      :ok = PubSub.subscribe_reports(device.id)

      sync(info, [probe()])
      assert_receive %Broadcast{event: "components:updated"}

      sync(info, [probe()], DateTime.add(@now, 60))
      refute_receive %Broadcast{event: "components:updated"}, 100
    end
  end

  describe "forget/3" do
    test "deletes the component and records who forgot it", %{device: device, device_info: info} do
      sync(info, [probe()])
      [component] = Components.list_for_device(device)

      assert :ok = Components.forget(device, component.id, "Jane")

      assert Components.list_for_device(device) == []
      assert {"forgotten", "Jane"} in history(device)
    end

    test "only forgets the device's own components", %{device: device, device_info: info} = context do
      sync(info, [probe()])
      [component] = Components.list_for_device(device)
      other = Fixtures.device_fixture(context.org, context.product, context.firmware)

      assert Components.forget(other, component.id, "Jane") == {:error, :not_found}
      assert [_] = Components.list_for_device(device)
    end
  end

  describe "product reads" do
    test "counts by model, with firmware versions most common first", %{product: product} = context do
      %{device_info: info} = context
      other = Fixtures.device_fixture(context.org, context.product, context.firmware)
      other_info = %{info | device_id: other.id}

      sync(info, [probe(), probe(%{"serial" => "b", "reachable" => false, "firmware_version" => "2.0.8"})])
      sync(other_info, [probe(%{"serial" => "c"})])

      assert [model] = Components.models(product)
      assert model.count == 3
      assert model.devices == 2
      assert model.missing == 1
      assert model.working == 2
      assert model.firmware_versions == [{"2.1.0", 2}, {"2.0.8", 1}]

      assert Components.product_counts(product) == %{components: 3, devices: 2, working: 2, missing: 1}
      assert Components.product_missing_count(product) == 1
    end
  end

  # ------------------------------------------------------- readings and state

  defp lock(overrides \\ %{}) do
    Map.merge(
      %{
        "namespace" => "zwave",
        "vendor" => "0129",
        "model" => "8002:0600",
        "serial" => "34028-23669",
        "name" => "Office lock",
        "firmware_version" => "2.2.1"
      },
      overrides
    )
  end

  defp state_history(device) do
    :ok = Buffer.flush(DeviceComponentHistory)

    DeviceComponentHistory
    |> where(device_id: ^device.id, event: "state_changed")
    |> order_by(asc: :timestamp)
    |> AnalyticsRepo.all()
    |> Enum.map(&{&1.state, &1.value, &1.detail})
  end

  defp report(serial, metrics, at \\ @now) do
    %{"namespace" => "zigbee", "serial" => serial, "timestamp" => DateTime.to_iso8601(at), "metrics" => metrics}
  end

  describe "snapshot state" do
    test "stores it, and records each value as a change", %{device: device, device_info: info} do
      sync(info, [lock(%{"state" => %{"lock" => "locked"}})])

      assert [%{state: %{"lock" => %{"value" => "locked", "since" => since}}}] = Components.list_for_device(device)
      assert {:ok, @now, 0} = DateTime.from_iso8601(since)
      assert state_history(device) == [{"lock", "locked", ""}]
    end

    test "keeps when a repeated value was set", %{device: device, device_info: info} do
      sync(info, [lock(%{"state" => %{"lock" => "locked"}})])
      sync(info, [lock(%{"state" => %{"lock" => "locked"}})], DateTime.add(@now, 60))

      assert [%{state: %{"lock" => %{"since" => since}}}] = Components.list_for_device(device)
      assert {:ok, @now, 0} = DateTime.from_iso8601(since)
      assert state_history(device) == [{"lock", "locked", ""}]
    end

    test "replaces what is stored, dropping a state left out", %{device: device, device_info: info} do
      sync(info, [lock(%{"state" => %{"lock" => "locked", "door" => "closed"}})])
      sync(info, [lock(%{"state" => %{"lock" => "unlocked"}})], DateTime.add(@now, 60))

      assert [%{state: state}] = Components.list_for_device(device)
      assert Map.keys(state) == ["lock"]
      assert state["lock"]["value"] == "unlocked"
    end

    test "an entry without state leaves it alone", %{device: device, device_info: info} do
      sync(info, [lock(%{"state" => %{"lock" => "locked"}})])
      sync(info, [lock(%{"name" => "Front lock"})], DateTime.add(@now, 60))

      assert [%{name: "Front lock", state: %{"lock" => %{"value" => "locked"}}}] = Components.list_for_device(device)
    end

    test "a bad state rejects the snapshot" do
      for state <- [
            %{"Lock" => "locked"},
            %{"lock" => 1},
            %{"lock" => ""},
            %{"lock" => String.duplicate("a", 65)},
            Map.new(1..9, &{"s#{&1}", "on"}),
            "locked"
          ] do
        assert Components.parse([lock(%{"state" => state})], @now) == {:error, :bad_state}
      end
    end
  end

  describe "parse_readings/2" do
    test "keeps at most 20 names a report, in sorted order, and only numbers" do
      metrics =
        1..25
        |> Map.new(&{"m#{String.pad_leading(to_string(&1), 2, "0")}", &1})
        |> Map.merge(%{"Bad" => 1, "label" => "warm"})

      assert [%{metrics: kept}] = Components.parse_readings([report("a", metrics)], @now)
      assert length(kept) == 20
      assert hd(kept) == {"m01", 1.0}
      assert List.last(kept) == {"m20", 20.0}
    end

    test "skips a report it can't read, and keeps the rest" do
      reports = [
        report("a", %{"temperature" => 21.4}),
        report("b", %{"temperature" => 21.4}, DateTime.add(@now, 25, :hour)),
        %{"namespace" => "zigbee", "metrics" => %{"temperature" => 1}},
        report("c", %{"label" => "warm"})
      ]

      assert [%{serial: "a"}] = Components.parse_readings(reports, @now)
    end

    test "reads at most 60 reports a message" do
      reports = for i <- 1..61, do: report("s#{i}", %{"temperature" => i})

      assert length(Components.parse_readings(reports, @now)) == 60
    end
  end

  describe "record_readings/2" do
    test "keeps the latest of each reading on the component, and every one in ClickHouse",
         %{device: device, device_info: info} do
      sync(info, [probe()])
      serial = probe()["serial"]

      reports = [
        report(serial, %{"temperature" => -18.6, "battery" => 88}, DateTime.add(@now, -60)),
        report(serial, %{"temperature" => -18.4}, @now)
      ]

      assert Components.record_readings(info, Components.parse_readings(reports, @now)) == %{stored: 2, unknown: 0}

      assert [%{readings: readings, readings_at: readings_at}] = Components.list_for_device(device)
      assert readings["temperature"]["value"] == -18.4
      assert readings["battery"]["value"] == 88.0
      assert readings_at == @now

      :ok = Buffer.flush(DeviceComponentReading)

      assert DeviceComponentReading
             |> where(device_id: ^device.id)
             |> select([r], {r.key, r.value, r.firmware_version})
             |> AnalyticsRepo.all()
             |> Enum.sort() ==
               [{"battery", 88.0, "2.1.0"}, {"temperature", -18.6, "2.1.0"}, {"temperature", -18.4, "2.1.0"}]
    end

    test "an older report doesn't replace a newer value", %{device: device, device_info: info} do
      sync(info, [probe()])
      serial = probe()["serial"]

      Components.record_readings(info, Components.parse_readings([report(serial, %{"temperature" => -18.4})], @now))

      Components.record_readings(
        info,
        Components.parse_readings([report(serial, %{"temperature" => -20.0}, DateTime.add(@now, -60))], @now)
      )

      assert [%{readings: %{"temperature" => %{"value" => -18.4}}}] = Components.list_for_device(device)
    end

    test "ignores a component no snapshot listed, and says how many", %{device: device, device_info: info} do
      sync(info, [probe()])

      assert Components.record_readings(
               info,
               Components.parse_readings([report("unknown", %{"temperature" => 1})], @now)
             ) ==
               %{stored: 0, unknown: 1}

      assert [%{readings: readings}] = Components.list_for_device(device)
      assert readings == %{}
    end

    test "doesn't touch another device's component with the same serial", %{device_info: info} = context do
      other = Fixtures.device_fixture(context.org, context.product, context.firmware)
      sync(%{info | device_id: other.id}, [probe()])

      assert Components.record_readings(info, Components.parse_readings([report(probe()["serial"], %{"t" => 1})], @now)) ==
               %{stored: 0, unknown: 1}
    end
  end

  describe "record_state/3" do
    setup %{device_info: info} do
      sync(info, [lock()])
      :ok
    end

    defp state_change(overrides \\ %{}) do
      Map.merge(
        %{
          "namespace" => "zwave",
          "serial" => "34028-23669",
          "state" => "lock",
          "value" => "unlocked",
          "changed_at" => DateTime.to_iso8601(DateTime.add(@now, -30)),
          "detail" => "by keypad, user 3"
        },
        overrides
      )
    end

    test "stores the change and records it", %{device: device, device_info: info} do
      assert Components.record_state(info, state_change(), @now) == :ok

      assert [%{state: %{"lock" => %{"value" => "unlocked", "detail" => "by keypad, user 3", "since" => since}}}] =
               Components.list_for_device(device)

      assert {:ok, at, 0} = DateTime.from_iso8601(since)
      assert at == DateTime.add(@now, -30)
      assert state_history(device) == [{"lock", "unlocked", "by keypad, user 3"}]
    end

    test "sending the same value again does nothing", %{device: device, device_info: info} do
      :ok = Components.record_state(info, state_change(), @now)
      :ok = Components.record_state(info, state_change(%{"changed_at" => DateTime.to_iso8601(@now)}), @now)

      assert length(state_history(device)) == 1
    end

    test "a change older than the stored value is ignored", %{device: device, device_info: info} do
      :ok = Components.record_state(info, state_change(), @now)

      :ok =
        Components.record_state(
          info,
          state_change(%{"value" => "locked", "changed_at" => "2026-11-24T11:00:00Z"}),
          @now
        )

      assert [%{state: %{"lock" => %{"value" => "unlocked"}}}] = Components.list_for_device(device)
    end

    test "a value a snapshot set is replaced by any change, whatever the device's clock says", %{
      device: device,
      device_info: info
    } do
      # The snapshot is stamped with the platform's clock; this device's runs
      # two minutes slow.
      sync(info, [lock(%{"state" => %{"lock" => "locked"}})])

      :ok =
        Components.record_state(
          info,
          state_change(%{"changed_at" => DateTime.to_iso8601(DateTime.add(@now, -120))}),
          @now
        )

      assert [%{state: %{"lock" => %{"value" => "unlocked"} = lock}}] = Components.list_for_device(device)
      refute Map.has_key?(lock, "snapshot")
    end

    test "an unbelievable changed_at is replaced by the arrival time", %{device: device, device_info: info} do
      :ok = Components.record_state(info, state_change(%{"changed_at" => "1970-01-01T00:00:00Z"}), @now)

      assert [%{state: %{"lock" => %{"since" => since}}}] = Components.list_for_device(device)
      assert {:ok, @now, 0} = DateTime.from_iso8601(since)
    end

    test "at most 8 states", %{device_info: info} do
      for i <- 1..8, do: :ok = Components.record_state(info, state_change(%{"state" => "s#{i}"}), @now)

      assert Components.record_state(info, state_change(%{"state" => "s9"}), @now) == {:error, :too_many_states}
    end

    test "rejects a malformed change or an unknown component", %{device_info: info} do
      assert Components.record_state(info, state_change(%{"state" => "Lock"}), @now) == {:error, :malformed}

      assert Components.record_state(info, state_change(%{"value" => String.duplicate("a", 65)}), @now) ==
               {:error, :malformed}

      assert Components.record_state(info, state_change(%{"detail" => String.duplicate("a", 256)}), @now) ==
               {:error, :malformed}

      assert Components.record_state(info, Map.delete(state_change(), "value"), @now) == {:error, :malformed}
      assert Components.record_state(info, state_change(%{"serial" => "other"}), @now) == {:error, :unknown_component}
    end
  end

  describe "history reads" do
    test "readings_history/2 averages the last six hours", %{device: device, device_info: info} do
      sync(info, [probe()])
      serial = probe()["serial"]

      reports =
        for minutes <- [30, 20, 10],
            do: report(serial, %{"temperature" => minutes}, DateTime.add(@now, -minutes, :minute))

      Components.record_readings(info, Components.parse_readings(reports, @now))
      :ok = Buffer.flush(DeviceComponentReading)

      [component] = Components.list_for_device(device)

      assert %{window: :six_hours, series: %{"temperature" => points}} = Components.readings_history(component, @now)
      assert Enum.map(points, &elem(&1, 1)) == [30.0, 20.0, 10.0]
    end

    test "readings_history/2 falls back to fourteen days for a rare reading", %{device: device, device_info: info} do
      sync(info, [probe()])
      serial = probe()["serial"]

      reports = for days <- [3, 2], do: report(serial, %{"battery" => 90 - days}, DateTime.add(@now, -days, :day))
      Components.record_readings(info, Components.parse_readings(reports, DateTime.add(@now, -2, :day)))
      Components.record_readings(info, Components.parse_readings([report(serial, %{"battery" => 88})], @now))
      :ok = Buffer.flush(DeviceComponentReading)

      [component] = Components.list_for_device(device)

      assert %{window: :fourteen_days, series: %{"battery" => [_, _, _]}} = Components.readings_history(component, @now)
    end

    test "state_history/2 gives the value before the window and the changes in it", %{device: device, device_info: info} do
      at = fn hours -> DateTime.to_iso8601(DateTime.add(@now, -hours, :hour)) end

      sync(info, [lock()], DateTime.add(@now, -30, :hour))
      :ok = Components.record_state(info, change_at("locked", at.(30)), @now)
      :ok = Components.record_state(info, change_at("unlocked", at.(5)), @now)
      :ok = Components.record_state(info, change_at("locked", at.(1)), @now)
      :ok = Buffer.flush(DeviceComponentHistory)

      [component] = Components.list_for_device(device)

      assert %{"lock" => %{before: "locked", changes: [%{value: "unlocked"}, %{value: "locked"}]}} =
               Components.state_history(component, DateTime.add(@now, -24, :hour))
    end
  end

  defp change_at(value, at) do
    %{"namespace" => "zwave", "serial" => "34028-23669", "state" => "lock", "value" => value, "changed_at" => at}
  end
end

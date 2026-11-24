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
    on_exit(fn -> AnalyticsRepo.query!("TRUNCATE TABLE device_component_history") end)

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
        "versions" => %{"firmware" => "2.1.0"}
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
      assert {:ok, [entry]} = Components.parse([probe(%{"versions" => %{"firmware" => ""}, "address" => ""})], @now)
      assert entry.versions == %{}
      assert entry.address == nil

      assert Components.parse([probe(%{"serial" => ""})], @now) == {:error, :malformed_entry}
    end

    test "reads every version a component holds, and none when it says nothing" do
      versions = %{"firmware" => "2.2.1", "keypad_config" => "7"}

      assert {:ok, [%{versions: ^versions}]} = Components.parse([probe(%{"versions" => versions})], @now)
      assert {:ok, [%{versions: %{}}]} = Components.parse([probe(%{"versions" => nil})], @now)
    end

    test "rejects versions it can't read" do
      assert Components.parse([probe(%{"versions" => "2.1.0"})], @now) == {:error, :malformed_entry}
      assert Components.parse([probe(%{"versions" => %{"firmware" => 2}})], @now) == {:error, :malformed_entry}
      assert Components.parse([probe(%{"versions" => %{"Keypad Config" => "7"}})], @now) == {:error, :bad_version_key}

      assert Components.parse([probe(%{"versions" => %{"firmware" => String.duplicate("1", 256)}})], @now) ==
               {:error, :too_long}

      too_many = Map.new(1..17, &{"part_#{&1}", "1"})
      assert Components.parse([probe(%{"versions" => too_many})], @now) == {:error, :too_many}
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

    test "a version change is recorded with what moved and the version it moved from", %{
      device: device,
      device_info: info
    } do
      sync(info, [probe(%{"versions" => %{"firmware" => "2.1.0", "keypad_config" => "6"}})])
      sync(info, [probe(%{"versions" => %{"firmware" => "2.1.0", "keypad_config" => "7"}})], DateTime.add(@now, 60))

      assert [component] = Components.list_for_device(device)
      assert component.versions == %{"firmware" => "2.1.0", "keypad_config" => "7"}
      assert DeviceComponent.firmware_version(component) == "2.1.0"
      assert history(device) == [{"appeared", ""}, {"version_changed", "6"}]

      :ok = Buffer.flush(DeviceComponentHistory)

      assert %{version_key: "keypad_config", versions: %{"keypad_config" => "7"}} =
               DeviceComponentHistory
               |> where(device_id: ^device.id, event: "version_changed")
               |> AnalyticsRepo.one()
    end

    test "a version reported for the first time, or no longer reported, isn't a change", %{
      device: device,
      device_info: info
    } do
      sync(info, [probe(%{"versions" => %{}})])
      sync(info, [probe()], DateTime.add(@now, 60))
      sync(info, [probe(%{"versions" => %{}})], DateTime.add(@now, 120))

      assert [%{versions: %{}}] = Components.list_for_device(device)
      assert history(device) == [{"appeared", ""}]
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

      sync(info, [probe(), probe(%{"serial" => "b", "reachable" => false, "versions" => %{"firmware" => "2.0.8"}})])
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
end

defmodule NervesHub.Devices.ComponentsTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.AuditLogs
  alias NervesHub.Devices.Components
  alias NervesHub.Devices.ComponentTopology
  alias NervesHub.Extensions.PubSub, as: ExtensionsPubSub
  alias NervesHub.Fixtures
  alias Phoenix.Socket.Broadcast

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    {:ok, %{user: user, org: org, product: product, device: device}}
  end

  @report %{
    "assemblies" => [
      %{
        "identifier" => "display",
        "label" => "Display",
        "metrics" => ["display_power_w"],
        "components" => [
          %{
            "identifier" => "panel",
            "label" => "Panel",
            "metrics" => ["display_fps"],
            "metadata" => ["panel_firmware"],
            "actions" => [%{"identifier" => "recalibrate", "label" => "Recalibrate"}],
            "modes" => [
              %{"identifier" => "display_mode", "values" => ["day", "night"]}
            ]
          }
        ]
      }
    ],
    "networks" => [
      %{
        "identifier" => "zwave",
        "label" => "Z-Wave",
        "peers" => [%{"identifier" => "zwave-26", "label" => "Motion sensor"}]
      }
    ]
  }

  describe "update_topology/2" do
    test "stores a sanitized topology and broadcasts", %{device: device} do
      :ok = ExtensionsPubSub.subscribe_reports(device.id)

      assert {:ok, %ComponentTopology{} = stored} = Components.update_topology(device.id, @report)

      assert stored.device_id == device.id
      assert [assembly] = stored.topology["assemblies"]
      assert assembly["identifier"] == "display"
      assert [component] = assembly["components"]
      assert component["identifier"] == "panel"
      assert [%{"identifier" => "recalibrate", "label" => "Recalibrate"}] = component["actions"]
      assert [mode] = component["modes"]
      assert mode["metadata_key"] == "display_mode"
      assert [network] = stored.topology["networks"]
      assert [%{"identifier" => "zwave-26"}] = network["peers"]

      assert_receive %Broadcast{event: "components:updated"}
    end

    test "replaces the previous topology", %{device: device} do
      assert {:ok, _} = Components.update_topology(device.id, @report)

      assert {:ok, _} =
               Components.update_topology(device.id, %{
                 "assemblies" => [%{"identifier" => "mainboard"}]
               })

      assert %ComponentTopology{topology: topology} = Components.get_topology(device.id)
      assert [%{"identifier" => "mainboard"}] = topology["assemblies"]
      assert topology["networks"] == []
    end

    test "drops unknown keys, junk entries and non-string values", %{device: device} do
      raw = %{
        "assemblies" => [
          %{"label" => "no identifier"},
          %{
            "identifier" => "ok",
            "surprise" => "dropped",
            "metrics" => ["fine", 42, %{"nested" => true}],
            "components" => [
              "not a map",
              %{"identifier" => "sensor", "actions" => [%{"label" => "no identifier"}]}
            ]
          }
        ],
        "networks" => "not a list",
        "extra" => "dropped"
      }

      assert {:ok, stored} = Components.update_topology(device.id, raw)

      assert [assembly] = stored.topology["assemblies"]
      assert assembly["identifier"] == "ok"
      refute Map.has_key?(assembly, "surprise")
      assert assembly["metrics"] == ["fine"]
      assert [%{"identifier" => "sensor", "actions" => []}] = assembly["components"]
      assert stored.topology["networks"] == []
      refute Map.has_key?(stored.topology, "extra")
    end

    test "rejects a report that is not a map", %{device: device} do
      assert {:error, :invalid_report} = Components.update_topology(device.id, ["nope"])
      assert Components.get_topology(device.id) == nil
    end

    test "rejects a topology over the size cap", %{device: device} do
      big = String.duplicate("x", 199)

      raw = %{
        "assemblies" =>
          for index <- 1..100 do
            %{
              "identifier" => "assembly-#{index}",
              "metadata" => Enum.map(1..40, fn n -> "#{big}-#{index}-#{n}" end)
            }
          end
      }

      assert {:error, %Ecto.Changeset{errors: errors}} = Components.update_topology(device.id, raw)
      assert {_msg, _opts} = errors[:topology]
    end
  end

  describe "request_action/4" do
    test "audits, records and broadcasts to the device", %{user: user, device: device} do
      :ok = ExtensionsPubSub.subscribe_device(device.id)

      assert {:ok, ref} = Components.request_action(user, device, "panel", "recalibrate")

      assert_receive %Broadcast{event: "components:action:run", payload: payload}
      assert payload["ref"] == ref
      assert payload["component"] == "panel"
      assert payload["action"] == "recalibrate"

      assert [log] = AuditLogs.logs_for(device)
      assert log.description =~ ~s(run action "recalibrate" on component "panel")
    end
  end

  describe "request_mode_change/5" do
    test "audits, records and broadcasts to the device", %{user: user, device: device} do
      :ok = ExtensionsPubSub.subscribe_device(device.id)

      assert {:ok, ref} = Components.request_mode_change(user, device, "panel", "display_mode", "night")

      assert_receive %Broadcast{event: "components:mode:set", payload: payload}
      assert payload["ref"] == ref
      assert payload["value"] == "night"

      assert [log] = AuditLogs.logs_for(device)
      assert log.description =~ ~s(set mode "display_mode" to "night" on component "panel")
    end
  end
end

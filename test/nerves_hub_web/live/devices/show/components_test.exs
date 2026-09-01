defmodule NervesHubWeb.Live.Devices.Show.ComponentsTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Accounts
  alias NervesHub.AuditLogs
  alias NervesHub.Devices.Components
  alias NervesHub.Devices.Health
  alias NervesHub.Devices.Metrics
  alias NervesHub.Extensions.PubSub, as: ExtensionsPubSub
  alias Phoenix.Socket.Broadcast

  @topology %{
    "assemblies" => [
      %{
        "identifier" => "display",
        "label" => "Display",
        "components" => [
          %{
            "identifier" => "panel",
            "label" => "Panel",
            "metrics" => ["display_fps"],
            "metadata" => ["panel_firmware"],
            "actions" => [
              %{"identifier" => "recalibrate", "label" => "Recalibrate"},
              %{"identifier" => "reset", "label" => "Factory reset", "confirm" => true}
            ],
            "modes" => [
              %{"identifier" => "display_mode", "label" => "Display mode", "values" => ["day", "night"]}
            ]
          }
        ]
      }
    ],
    "networks" => [
      %{
        "identifier" => "zwave",
        "label" => "Z-Wave",
        "metrics" => ["zwave_rssi"],
        "peers" => [%{"identifier" => "zwave-26", "label" => "Motion sensor"}]
      }
    ]
  }

  defp enable_components(product) do
    {:ok, _product} = NervesHub.Products.enable_extension_setting(product, "components")
    :ok
  end

  defp seed_components(device) do
    {:ok, _} = Components.update_topology(device.id, @topology)
    {:ok, _} = Metrics.save_metrics(device.id, %{"display_fps" => 59.9})

    {:ok, _} =
      Health.save_device_health(%{
        "device_id" => device.id,
        "data" => %{"metadata" => %{"panel_firmware" => "v42", "display_mode" => "day"}},
        "status" => :healthy,
        "status_reasons" => nil
      })

    :ok
  end

  defp device_path(fixture) do
    %{device: device, org: org, product: product} = fixture
    "/org/#{org.name}/#{product.name}/devices/#{device.identifier}"
  end

  test "the details tab shows assemblies as component boxes", %{conn: conn, fixture: fixture} do
    :ok = seed_components(fixture.device)

    conn
    |> visit(device_path(fixture))
    |> assert_has("div", text: "Display")
    |> assert_has("span", text: "Panel")
    |> assert_has("span", text: "Display fps")
    |> assert_has("span", text: "59.90")
    |> assert_has("span", text: "Panel firmware")
    |> assert_has("span", text: "v42")
    |> assert_has("button", text: "Recalibrate")
    |> assert_has("option[selected]", text: "day")
    # Only the human name is shown; the identifier stays machine addressing.
    |> refute_has("span", text: "display_fps")
    # An action reported with confirm gets a confirmation dialog.
    |> assert_has(~s(button[data-confirm='Run "Factory reset" on "Panel"?']), text: "Factory reset")
    |> refute_has("button[data-confirm]", text: "Recalibrate")
  end

  test "a device without a topology shows no component boxes", %{conn: conn, fixture: fixture} do
    conn
    |> visit(device_path(fixture))
    |> refute_has("button", text: "Recalibrate")
    |> refute_has("a", text: "View networks")
  end

  test "the details tab summarizes networks with their stats", %{conn: conn, fixture: fixture} do
    :ok = seed_components(fixture.device)
    {:ok, _} = Metrics.save_metrics(fixture.device.id, %{"zwave_rssi" => -61.0})

    conn
    |> visit(device_path(fixture))
    |> assert_has("div", text: "Networks")
    |> assert_has("span", text: "Z-Wave")
    |> assert_has("span", text: "1 peer")
    |> assert_has("span", text: "Zwave rssi")
    |> assert_has("span", text: "-61.00")
    |> assert_has("a", text: "View networks")
    # The peers themselves belong to the Networks tab, not the summary.
    |> refute_has("span", text: "Motion sensor")
  end

  test "a health report updates metadata and mode values without a reload", %{
    conn: conn,
    fixture: fixture
  } do
    %{device: device} = fixture
    :ok = seed_components(device)

    session = visit(conn, device_path(fixture))
    assert_has(session, "option[selected]", text: "day")

    {:ok, _} =
      Health.save_device_health(%{
        "device_id" => device.id,
        "data" => %{"metadata" => %{"panel_firmware" => "v43", "display_mode" => "night"}},
        "status" => :healthy,
        "status_reasons" => nil
      })

    :ok = ExtensionsPubSub.broadcast_report(device.id, "health_check_report", %{})

    session
    |> assert_has("option[selected]", text: "night", timeout: 1_000)
    |> assert_has("span", text: "v43")
  end

  test "clicking an action sends the request to the device and audits it", %{
    conn: conn,
    fixture: fixture
  } do
    %{device: device, user: user, product: product} = fixture
    :ok = seed_components(device)
    :ok = enable_components(product)
    :ok = ExtensionsPubSub.subscribe_device(device.id)

    before_count = device |> AuditLogs.logs_for() |> length()

    conn
    |> visit(device_path(fixture))
    |> click_button("Recalibrate")
    |> assert_has("div", text: ~s(Requested action "recalibrate" on "panel".))

    assert_receive %Broadcast{event: "components:action:run", payload: payload}
    assert payload["component"] == "panel"
    assert payload["action"] == "recalibrate"
    assert is_binary(payload["ref"])

    logs = AuditLogs.logs_for(device)
    assert length(logs) == before_count + 1
    assert List.last(logs).description =~ user.name
  end

  test "changing a mode sends the request to the device", %{conn: conn, fixture: fixture} do
    %{device: device, product: product} = fixture
    :ok = seed_components(device)
    :ok = enable_components(product)
    :ok = ExtensionsPubSub.subscribe_device(device.id)

    conn
    |> visit(device_path(fixture))
    |> select("Display mode", option: "night")
    |> assert_has("div", text: ~s(Requested mode "display_mode" be set to "night" on "panel".))

    assert_receive %Broadcast{event: "components:mode:set", payload: payload}
    assert payload["component"] == "panel"
    assert payload["mode"] == "display_mode"
    assert payload["value"] == "night"
  end

  test "an action result reported by the device is shown", %{conn: conn, fixture: fixture} do
    %{device: device} = fixture
    :ok = seed_components(device)

    session = visit(conn, device_path(fixture))

    :ok =
      ExtensionsPubSub.broadcast_report(device.id, "components:action_result", %{
        "component" => "panel",
        "action" => "recalibrate",
        "status" => "ok",
        "output" => "calibration complete"
      })

    assert_has(session, "div", text: ~s(Action "recalibrate" on "panel" completed: calibration complete))
  end

  test "controls are disabled when the extension is not enabled", %{conn: conn, fixture: fixture} do
    # Topology stored, but the extension has since been switched off (or was
    # never on): the boxes stay — the topology is still true — but a request
    # into the void is not worth offering.
    :ok = seed_components(fixture.device)

    conn
    |> visit(device_path(fixture))
    |> assert_has("span", text: "Panel")
    |> assert_has("button[disabled]", text: "Recalibrate")
    |> assert_has("select[disabled]")
  end

  test "a viewer cannot invoke actions", %{conn: conn, fixture: fixture} do
    %{device: device, org: org, user: user, product: product} = fixture
    :ok = seed_components(device)
    # Enabled, so the disabled state below is the role's doing.
    :ok = enable_components(product)

    {:ok, org_user} = Accounts.get_org_user(org, user)
    {:ok, _} = Accounts.change_org_user_role(org_user, :view)

    conn
    |> visit(device_path(fixture))
    |> assert_has("button[disabled]", text: "Recalibrate")
  end
end

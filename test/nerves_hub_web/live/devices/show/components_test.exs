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
            "actions" => [%{"identifier" => "recalibrate", "label" => "Recalibrate"}],
            "modes" => [
              %{"identifier" => "display_mode", "label" => "Display mode", "values" => ["day", "night"]}
            ]
          }
        ]
      }
    ],
    "networks" => []
  }

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
    |> assert_has("span", text: "panel")
    |> assert_has("span", text: "display_fps")
    |> assert_has("span", text: "59.90")
    |> assert_has("span", text: "panel_firmware")
    |> assert_has("span", text: "v42")
    |> assert_has("button", text: "Recalibrate")
    |> assert_has("option[selected]", text: "day")
  end

  test "a device without a topology shows no component boxes", %{conn: conn, fixture: fixture} do
    conn
    |> visit(device_path(fixture))
    |> refute_has("button", text: "Recalibrate")
  end

  test "clicking an action sends the request to the device and audits it", %{
    conn: conn,
    fixture: fixture
  } do
    %{device: device, user: user} = fixture
    :ok = seed_components(device)
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
    %{device: device} = fixture
    :ok = seed_components(device)
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

  test "a viewer cannot invoke actions", %{conn: conn, fixture: fixture} do
    %{device: device, org: org, user: user} = fixture
    :ok = seed_components(device)

    {:ok, org_user} = Accounts.get_org_user(org, user)
    {:ok, _} = Accounts.change_org_user_role(org_user, :view)

    conn
    |> visit(device_path(fixture))
    |> assert_has("button[disabled]", text: "Recalibrate")
  end
end

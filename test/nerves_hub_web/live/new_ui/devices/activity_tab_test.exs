defmodule NervesHubWeb.Live.NewUI.Devices.ActivityTabTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.AuditLogs.DeviceTemplates

  setup %{conn: conn} do
    [conn: init_test_session(conn, %{"new_ui" => true})]
  end

  test "no audit log history exists for the device", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/activity")
    |> assert_has("span", text: "No audit logs found for the device.")
  end

  test "audit log history exists for the device", %{
    conn: conn,
    org: org,
    product: product,
    device: device,
    user: user
  } do
    # Add audit log item for the device
    DeviceTemplates.audit_reboot(user, device)

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/activity")
    |> assert_has("div", text: "User #{user.name} rebooted device #{device.identifier}")
  end
end

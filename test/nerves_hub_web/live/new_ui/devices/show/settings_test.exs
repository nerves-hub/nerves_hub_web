defmodule NervesHubWeb.Live.NewUI.Devices.Show.SettingsTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  setup %{conn: conn, fixture: %{device: device}} = context do
    conn = init_test_session(conn, %{"new_ui" => true})

    Map.put(context, :conn, conn)
  end

  test "updating first in line for updates", %{
    conn: conn,
    org: org,
    product: product,
    device: device,
    user: user
  } do
    refute device.first_in_line_for_updates

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/settingz")
    |> check("First in line", exact: false)
    |> submit()

    assert Repo.reload(device) |> Map.get(:first_in_line_for_updates)
  end
end

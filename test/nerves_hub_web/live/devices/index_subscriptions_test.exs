defmodule NervesHubWeb.Live.Devices.IndexSubscriptionsTest do
  use NervesHubWeb.ConnCase.Browser, async: true
  use AssertEventually, timeout: 2000, interval: 50

  import Phoenix.LiveViewTest

  alias NervesHub.Fixtures

  setup %{user: user, org: org, org_key: org_key, tmp_dir: tmp_dir} do
    product = Fixtures.product_fixture(user, org, %{name: "Subscriptions"})
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

    devices =
      for n <- 1..3 do
        Fixtures.device_fixture(org, product, firmware, %{identifier: "sub-device-#{n}"})
      end

    %{product: product, devices: devices}
  end

  test "subscribes once per device on the page", %{conn: conn, org: org, product: product, devices: devices} do
    {:ok, view, _html} = live(conn, devices_path(org, product))

    for device <- devices do
      assert_eventually(subscriptions(view.pid, device) == 1)
    end
  end

  # A duplicate subscription would have the LiveView handle every event for that
  # device twice, and each one can trigger a refresh.
  test "a refresh does not accumulate duplicate subscriptions", %{
    conn: conn,
    org: org,
    product: product,
    devices: devices
  } do
    {:ok, view, _html} = live(conn, devices_path(org, product))
    [device | _] = devices

    assert_eventually(subscriptions(view.pid, device) == 1)

    send(view.pid, :refresh_device_list)
    _ = render(view)

    for device <- devices do
      assert_eventually(subscriptions(view.pid, device) == 1)
    end
  end

  test "devices that leave the page are unsubscribed", %{
    conn: conn,
    org: org,
    product: product,
    devices: devices
  } do
    {:ok, view, _html} = live(conn, devices_path(org, product))
    [kept, dropped, also_dropped] = devices

    for device <- devices do
      assert_eventually(subscriptions(view.pid, device) == 1)
    end

    # Patch rather than re-mount, so the filter narrows the page on the same
    # process that holds the subscriptions.
    _ = render_patch(view, devices_path(org, product) <> "?identifier=#{kept.identifier}")

    assert_eventually(subscriptions(view.pid, dropped) == 0)
    assert_eventually(subscriptions(view.pid, also_dropped) == 0)
    assert subscriptions(view.pid, kept) == 1
  end

  defp devices_path(org, product), do: "/org/#{org.name}/#{product.name}/devices"

  defp subscriptions(view_pid, device) do
    NervesHub.PubSub
    |> Registry.lookup("internal:device:#{device.id}")
    |> Enum.count(fn {subscriber, _} -> subscriber == view_pid end)
  end
end

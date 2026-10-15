defmodule NervesHubWeb.Live.Devices.Show.LocalShellTabTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Consoles
  alias NervesHub.Devices
  alias NervesHub.Products
  alias NervesHub.Support.ConsoleStandIn
  alias NervesHub.Support.LocalShellStandIn

  test "the local shell extension is enabled for the product", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    {:ok, _product} = Products.disable_extension_setting(product, "local_shell")
    {:ok, _device} = Devices.disable_extension_setting(device, "local_shell")

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/local_shell")
    |> assert_has("p", text: "The device local shell isn't currently enabled.", timeout: 500)
    |> assert_has("p", text: "Please check your device and product settings to ensure that the local shell is enabled.")
  end

  test "the local shell extension isn't enabled for the device", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    {:ok, _product} = Products.enable_extension_setting(product, "local_shell")
    {:ok, _device} = Devices.disable_extension_setting(device, "local_shell")

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/local_shell")
    |> assert_has("p", text: "The device local shell isn't currently enabled.", timeout: 500)
    |> assert_has("p", text: "Please check your device and product settings to ensure that the local shell is enabled.")
  end

  test "the local shell isn't active", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    {:ok, _product} = Products.enable_extension_setting(product, "local_shell")
    {:ok, _device} = Devices.enable_extension_setting(device, "local_shell")

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/local_shell")
    |> assert_has("div", text: "The device's local shell isn't currently available.", timeout: 500)
  end

  test "the local shell UI is shown", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    {:ok, _product} = Products.enable_extension_setting(product, "local_shell")
    {:ok, _device} = Devices.enable_extension_setting(device, "local_shell")

    # Stand in for an attached device-side LocalShell extension, which answers
    # the tab's locate.
    _shell = LocalShellStandIn.start(device.id)

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/local_shell")
    |> assert_has("#local-shell", timeout: 1000)
    |> refute_has("div", text: "The device's local shell isn't currently available.", timeout: 500)
  end

  test "the local shell availability updates live when the shell detaches", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    {:ok, _product} = Products.enable_extension_setting(product, "local_shell")
    {:ok, _device} = Devices.enable_extension_setting(device, "local_shell")

    # Stand in for an attached device-side LocalShell extension.
    _shell = LocalShellStandIn.start(device.id)

    session =
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/local_shell")
      |> assert_has("#local-shell", timeout: 1000)

    # The shell detaches while the tab is open. The extension tells the page,
    # which should flip the indicator without a reload.
    :ok = Consoles.PubSub.broadcast_local_shell_detached(device.id)

    session
    |> assert_has("div", text: "The device's local shell isn't currently available.", timeout: 1000)
  end

  test "the local shell availability updates live when the shell attaches", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    {:ok, _product} = Products.enable_extension_setting(product, "local_shell")
    {:ok, _device} = Devices.enable_extension_setting(device, "local_shell")

    session =
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/local_shell")
      |> assert_has("div", text: "The device's local shell isn't currently available.", timeout: 500)

    :ok = Consoles.PubSub.broadcast_local_shell_attached(device.id)

    assert_has(session, "#local-shell", timeout: 1000)
  end

  test "switching to the shell tab releases the console's monitor", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    {:ok, _product} = Products.enable_extension_setting(product, "local_shell")
    {:ok, _device} = Devices.enable_extension_setting(device, "local_shell")

    # The console tab monitors the console channel it found, so there has to be
    # one to find.
    console = ConsoleStandIn.start(device.id)

    # The tabs are `patch` links, so both tabs run in the same LiveView process
    # and a monitor taken by one outlives a switch to the other.
    session =
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/console")
      |> assert_has("#console", timeout: 1000)
      |> unwrap(fn view ->
        send(self(), {:live_view, view.pid})
        render(view)
      end)

    assert_received {:live_view, live_view}

    assert monitoring_process?(live_view, console)

    session
    |> click_link("System Shell")
    |> assert_has("h1", text: device.identifier)

    refute monitoring_process?(live_view, console)
  end

  defp monitoring_process?(pid, monitored) do
    {:monitors, monitors} = Process.info(pid, :monitors)
    {:process, monitored} in monitors
  end
end

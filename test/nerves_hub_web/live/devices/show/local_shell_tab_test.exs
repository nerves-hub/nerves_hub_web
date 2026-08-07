defmodule NervesHubWeb.Live.Devices.Show.LocalShellTabTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Consoles
  alias NervesHub.Devices
  alias NervesHub.Products

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

    # Stand in for an attached device-side LocalShell extension by joining the
    # local-shell registry group; `local_shell_active?/1` then reports available.
    :ok = Consoles.PubSub.join_local_shell(device.id)

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/local_shell")
    |> assert_has("#local-shell")
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
    :ok = Consoles.PubSub.join_local_shell(device.id)

    session =
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/local_shell")
      |> assert_has("#local-shell")

    # The shell detaches while the tab is open; the monitor should flip the
    # indicator without a page reload.
    :ok = Consoles.PubSub.leave_local_shell(device.id)

    session
    |> assert_has("div", text: "The device's local shell isn't currently available.", timeout: 1000)
  end
end

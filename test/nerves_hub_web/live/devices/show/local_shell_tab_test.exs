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

  test "switching terminal tabs leaves only the active tab's liveness monitor", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    {:ok, _product} = Products.enable_extension_setting(product, "local_shell")
    {:ok, _device} = Devices.enable_extension_setting(device, "local_shell")

    # The tabs are `patch` links, so both tabs run in the same LiveView process
    # and a monitor taken by one outlives a switch to the other.
    session =
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/console")
      |> unwrap(fn view ->
        send(self(), {:live_view, view.pid})
        render(view)
      end)

    assert_received {:live_view, live_view}

    assert monitoring?(live_view, "console/#{device.id}")
    refute monitoring?(live_view, "local_shell/#{device.id}")

    session
    |> click_link("System Shell")
    |> assert_has("h1", text: device.identifier)

    assert monitoring?(live_view, "local_shell/#{device.id}")
    refute monitoring?(live_view, "console/#{device.id}")
  end

  # See the note in NervesHub.Consoles.PubSubTest: a monitor registration is not
  # observable through delivery, so this reaches into `Group`'s registry.
  defp monitoring?(pid, key) do
    NervesHub.Group
    |> Group.registry_name()
    |> Registry.lookup({NervesHub.Group, nil, {:exact, key}})
    |> Enum.any?(fn {entry_pid, _} -> entry_pid == pid end)
  end
end

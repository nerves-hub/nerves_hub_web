defmodule NervesHubWeb.Live.NewUI.Devices.LocalShellTabTest do
  use NervesHubWeb.ConnCase.Browser, async: false

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
    |> assert_has("div", text: "Checking if the device's local shell is available...")
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
    |> assert_has("div", text: "Checking if the device's local shell is available...")
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
    |> assert_has("div", text: "Checking if the device's local shell is available...")
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

    topic = "device:#{device.id}:extensions"
    Phoenix.PubSub.subscribe(NervesHub.PubSub, topic)

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/local_shell")
    |> assert_has("div", text: "Checking if the device's local shell is available...")
    |> unwrap(fn view ->
      assert_receive {NervesHub.Extensions.LocalShell, {:active?, pid}}
      send(pid, :active)
      render(view)
    end)
    |> assert_has("#local-shell")
    |> refute_has("div", text: "The device's local shell isn't currently available.", timeout: 500)
  end
end

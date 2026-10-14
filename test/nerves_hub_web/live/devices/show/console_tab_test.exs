defmodule NervesHubWeb.Live.Devices.Show.ConsoleTabTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Consoles
  alias NervesHub.Support.ConsoleStandIn

  @unavailable "The device console isn't currently available."

  test "the console is unavailable when nothing answers", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    conn
    |> visit(console_path(org, product, device))
    |> assert_has("div", text: @unavailable)
    |> refute_has("#console")
  end

  test "the console is shown when the device's console channel answers", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    _console = ConsoleStandIn.start(device.id)

    conn
    |> visit(console_path(org, product, device))
    |> assert_has("#console", timeout: 1000)
    |> refute_has("div", text: @unavailable)
  end

  test "the console becomes unavailable when its channel goes away", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    console = ConsoleStandIn.start(device.id)

    session =
      conn
      |> visit(console_path(org, product, device))
      |> assert_has("#console", timeout: 1000)

    :ok = ConsoleStandIn.stop(console)

    # The tab looks again before giving up, in case the device came back on
    # another console channel, so this takes the locate timeout.
    assert_has(session, "div", text: @unavailable, timeout: 3000)
  end

  test "the console appears when the device's console channel joins", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    session =
      conn
      |> visit(console_path(org, product, device))
      |> assert_has("div", text: @unavailable)

    _console = ConsoleStandIn.start(device.id)
    :ok = Consoles.PubSub.broadcast_console_joined(device.id)

    assert_has(session, "#console", timeout: 1000)
  end

  defp console_path(org, product, device) do
    "/org/#{org.name}/#{product.name}/devices/#{device.identifier}/console"
  end
end

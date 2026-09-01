defmodule NervesHubWeb.ComponentsExtensionTest do
  use NervesHubWeb.ChannelCase
  use DefaultMocks

  alias NervesHub.Devices.Components
  alias NervesHub.Extensions.PubSub
  alias NervesHub.Fixtures
  alias NervesHub.Products
  alias NervesHubWeb.DeviceSocket
  alias NervesHubWeb.ExtensionsChannel
  alias Phoenix.Socket.Broadcast

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)
    %{db_cert: certificate, cert: _cert} = Fixtures.device_certificate_fixture(device)

    # Opt in at the product level, which is where every extension starts off.
    # Health too: an action/mode result asks for a health refresh when the
    # device is allowed to report health.
    {:ok, _product} = Products.enable_extension_setting(product, "components")
    {:ok, _product} = Products.enable_extension_setting(product, "health")

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    %{user: user, device: device, socket: socket, certificate: certificate}
  end

  defp join_and_attach(socket) do
    assert {:ok, attach_list, socket} =
             subscribe_and_join(socket, ExtensionsChannel, "extensions", %{
               "device_api_version" => "2.2.0",
               "components" => "0.0.1"
             })

    assert "components" in attach_list

    push(socket, "components:attached")

    socket
  end

  @report %{
    "assemblies" => [
      %{
        "identifier" => "display",
        "label" => "Display",
        "components" => [
          %{
            "identifier" => "panel",
            "metrics" => ["display_fps"],
            "actions" => [%{"identifier" => "recalibrate", "label" => "Recalibrate"}],
            "modes" => [%{"identifier" => "display_mode", "values" => ["day", "night"]}]
          }
        ]
      }
    ],
    "networks" => [
      %{"identifier" => "zwave", "peers" => [%{"identifier" => "zwave-26"}]}
    ]
  }

  test "asks the device for its topology once on attach", %{socket: socket} do
    join_and_attach(socket)

    assert_push("components:request", %{})
  end

  test "stores what the device reports and tells the UI", %{device: device, socket: socket} do
    socket = join_and_attach(socket)

    :ok = PubSub.subscribe_reports(device.id)

    push(socket, "components:report", @report)

    assert_receive %Broadcast{event: "components:updated"}

    assert %{topology: topology} = Components.get_topology(device.id)
    assert [%{"identifier" => "display", "components" => [component]}] = topology["assemblies"]
    assert component["identifier"] == "panel"
    assert [%{"identifier" => "zwave"}] = topology["networks"]
  end

  test "an unusable report does not take the channel down", %{device: device, socket: socket} do
    socket = join_and_attach(socket)

    push(socket, "components:report", %{"assemblies" => "garbage", "networks" => 42})

    # The channel is still alive and the (empty) topology was stored.
    assert %{topology: topology} =
             wait_until(fn -> Components.get_topology(device.id) end)

    assert topology == %{"assemblies" => [], "networks" => []}
    assert Process.alive?(socket.channel_pid)
  end

  test "an operator action request reaches the device as an explicit message", %{
    user: user,
    device: device,
    socket: socket
  } do
    socket = join_and_attach(socket)
    assert_push("components:request", %{})

    {:ok, ref} = Components.request_action(user, device, "panel", "recalibrate")

    assert_push("components:action:run", payload)
    assert payload["ref"] == ref
    assert payload["component"] == "panel"
    assert payload["action"] == "recalibrate"

    # The device answers, and whoever watches the device page hears about it.
    :ok = PubSub.subscribe_reports(device.id)

    push(socket, "components:action:result", %{
      "ref" => ref,
      "component" => "panel",
      "action" => "recalibrate",
      "status" => "ok",
      "output" => "calibration complete"
    })

    assert_receive %Broadcast{event: "components:action_result", payload: result}
    assert result["ref"] == ref
    assert result["status"] == "ok"
    assert result["output"] == "calibration complete"

    # The action likely changed the values the component boxes show, so the
    # device is asked for a fresh health report rather than waiting out the
    # regular interval.
    assert_push("health:check", %{})
  end

  test "an operator mode change reaches the device and the result comes back", %{
    user: user,
    device: device,
    socket: socket
  } do
    socket = join_and_attach(socket)
    assert_push("components:request", %{})

    {:ok, ref} = Components.request_mode_change(user, device, "panel", "display_mode", "night")

    assert_push("components:mode:set", payload)
    assert payload["ref"] == ref
    assert payload["mode"] == "display_mode"
    assert payload["value"] == "night"

    :ok = PubSub.subscribe_reports(device.id)

    push(socket, "components:mode:result", %{
      "ref" => ref,
      "component" => "panel",
      "mode" => "display_mode",
      "value" => "night",
      "status" => "ok",
      "output" => ""
    })

    assert_receive %Broadcast{event: "components:mode_result", payload: result}
    assert result["ref"] == ref
    assert result["status"] == "ok"

    # A mode drives a metadata value, so the refresh matters even more here.
    assert_push("health:check", %{})
  end

  test "no health refresh is requested when the device may not report health", %{
    user: user,
    device: device,
    certificate: certificate
  } do
    product = Products.get_product!(device.product_id)
    {:ok, _product} = Products.disable_extension_setting(product, "health")

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    socket = join_and_attach(socket)
    assert_push("components:request", %{})

    {:ok, ref} = Components.request_action(user, device, "panel", "recalibrate")
    assert_push("components:action:run", _payload)

    push(socket, "components:action:result", %{
      "ref" => ref,
      "component" => "panel",
      "action" => "recalibrate",
      "status" => "ok",
      "output" => ""
    })

    refute_push("health:check", %{})
  end

  test "is not offered when the product has not enabled it", %{device: device, certificate: certificate} do
    product = Products.get_product!(device.product_id)
    {:ok, _product} = Products.disable_extension_setting(product, "components")

    # A fresh connection, since what a device may use is settled when it
    # authenticates.
    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    assert {:ok, attach_list, _socket} =
             subscribe_and_join(socket, ExtensionsChannel, "extensions", %{
               "device_api_version" => "2.2.0",
               "components" => "0.0.1"
             })

    refute "components" in attach_list
  end

  # The report is handled by the channel asynchronously; poll rather than sleep.
  defp wait_until(fun, attempts \\ 50) do
    case fun.() do
      nil when attempts > 0 ->
        Process.sleep(20)
        wait_until(fun, attempts - 1)

      result ->
        result
    end
  end
end

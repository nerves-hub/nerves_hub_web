defmodule NervesHubDeviceWeb.DeviceControllerTest do
  use NervesHubDeviceWeb.ConnCase, async: false
  alias NervesHubWebCore.{Deployments, Fixtures, Devices}

  describe "device" do
    test "identify a device", %{conn: conn, device: device} do
      conn = get(conn, device_path(conn, :me))
      assert json_response(conn, 200)["data"]["identifier"] == device.identifier
    end

    test "gets available update", %{
      conn: conn,
      org_key: org_key,
      deployment: deployment,
      product: product
    } do
      # Make sure there is no update available
      conn = get(conn, device_path(conn, :update))
      assert json_response(conn, 200)["data"]["update_available"] == false

      # Create a new firmware and active deployment for the device
      new_firmware = Fixtures.firmware_fixture(org_key, product)
      params = %{firmware_id: new_firmware.id, is_active: true}
      {:ok, _} = Deployments.update_deployment(deployment, params)

      # Should be an update available now.
      conn = get(conn, device_path(conn, :update))
      assert json_response(conn, 200)["data"]["update_available"]
    end

    test "last used is updated", %{conn: conn, device: device} do
      [%{last_used: last_used}] = Devices.get_device_certificates(device)
      get(conn, device_path(conn, :me))
      [%{last_used: updated_last_used}] = Devices.get_device_certificates(device)
      assert last_used != updated_last_used
    end
  end
end

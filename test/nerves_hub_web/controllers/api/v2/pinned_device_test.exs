defmodule NervesHubWeb.API.V2.PinnedDeviceTest do
  use NervesHubWeb.AshAPIConnCase, async: false

  alias NervesHub.Fixtures

  setup %{user: user, org: org, product: product, tmp_dir: tmp_dir} do
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    [device: device]
  end

  describe "index" do
    test "lists pinned devices", %{conn: conn, user: user, device: device} do
      # Pin the device first
      NervesHub.Repo.insert!(%NervesHub.Devices.PinnedDevice{
        user_id: user.id,
        device_id: device.id
      })

      conn = get(conn, "/api/v2/pinned-devices")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      assert length(resp["data"]) >= 1
    end
  end

  describe "create" do
    test "pins a device for a user", %{conn: conn, user: user, device: device} do
      conn =
        post(conn, "/api/v2/pinned-devices", %{
          "data" => %{
            "type" => "pinned-device",
            "attributes" => %{
              "user_id" => user.id,
              "device_id" => device.id
            }
          }
        })

      resp = json_response(conn, 201)
      assert resp["data"]["attributes"]["user_id"] == user.id
      assert resp["data"]["attributes"]["device_id"] == device.id
    end
  end

  describe "list_by_user" do
    test "lists pinned devices by user", %{conn: conn, user: user, device: device} do
      NervesHub.Repo.insert!(%NervesHub.Devices.PinnedDevice{
        user_id: user.id,
        device_id: device.id
      })

      conn = get(conn, "/api/v2/pinned-devices/by-user/#{user.id}")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      assert length(resp["data"]) >= 1
    end
  end

  describe "delete" do
    test "unpins a device", %{conn: conn, user: user, device: device} do
      pinned =
        NervesHub.Repo.insert!(%NervesHub.Devices.PinnedDevice{
          user_id: user.id,
          device_id: device.id
        })

      conn = delete(conn, "/api/v2/pinned-devices/#{pinned.id}")
      assert response(conn, 200)
    end
  end
end

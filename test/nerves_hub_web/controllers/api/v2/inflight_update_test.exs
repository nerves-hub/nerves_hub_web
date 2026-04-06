defmodule NervesHubWeb.API.V2.InflightUpdateTest do
  use NervesHubWeb.AshAPIConnCase, async: false

  alias NervesHub.Fixtures

  setup %{user: user, org: org, product: product, tmp_dir: tmp_dir} do
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)
    deployment_group = Fixtures.deployment_group_fixture(firmware)

    {:ok, inflight} = Fixtures.inflight_update(device, deployment_group)

    [device: device, deployment_group: deployment_group, inflight: inflight]
  end

  describe "index" do
    test "lists inflight updates", %{conn: conn} do
      conn = get(conn, "/api/v2/inflight-updates")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      assert length(resp["data"]) >= 1
    end
  end

  describe "show" do
    test "returns an inflight update by id", %{conn: conn, inflight: inflight} do
      conn = get(conn, "/api/v2/inflight-updates/#{inflight.id}")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["status"] == "pending"
    end
  end

  describe "list_by_device" do
    test "lists inflight updates by device", %{conn: conn, device: device} do
      conn = get(conn, "/api/v2/inflight-updates/by-device/#{device.id}")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      assert length(resp["data"]) >= 1
    end
  end

  describe "list_by_deployment" do
    test "lists inflight updates by deployment", %{conn: conn, deployment_group: dg} do
      conn = get(conn, "/api/v2/inflight-updates/by-deployment/#{dg.id}")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      assert length(resp["data"]) >= 1
    end
  end
end

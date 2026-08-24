defmodule NervesHubWeb.DeploymentGroupControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Devices
  alias NervesHub.Fixtures

  test "download device ids csv", %{
    conn: conn,
    org: org,
    product: product,
    firmware: firmware,
    deployment_group: deployment_group
  } do
    device_b =
      Fixtures.device_fixture(org, product, firmware, %{
        deployment_id: deployment_group.id,
        identifier: "device-b"
      })

    device_a =
      Fixtures.device_fixture(org, product, firmware, %{
        deployment_id: deployment_group.id,
        identifier: "device-a"
      })

    deleted_device =
      Fixtures.device_fixture(org, product, firmware, %{
        deployment_id: deployment_group.id,
        identifier: "device-deleted"
      })

    {:ok, _device} = Devices.delete_device(deleted_device)

    _device_outside_group = Fixtures.device_fixture(org, product, firmware)

    conn = get(conn, ~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/device_ids/download")

    [str] = Plug.Conn.get_resp_header(conn, "content-disposition")

    assert str =~ "attachment; filename"

    [header | rows] = NimbleCSV.RFC4180.parse_string(conn.resp_body, skip_headers: false)

    assert header == ["identifier"]
    assert rows == [[device_a.identifier], [device_b.identifier]]
  end

  test "download device ids csv for unknown deployment group returns 404", %{
    conn: conn,
    org: org,
    product: product
  } do
    conn = get(conn, ~p"/org/#{org}/#{product}/deployment_groups/does-not-exist/device_ids/download")

    assert conn.status == 404
  end
end

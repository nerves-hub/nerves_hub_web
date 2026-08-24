defmodule NervesHubWeb.DeploymentGroupControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Fixtures

  test "download device ids csv", %{
    conn: conn,
    org: org,
    product: product,
    firmware: firmware,
    deployment_group: deployment_group
  } do
    device_in_group =
      Fixtures.device_fixture(org, product, firmware, %{deployment_id: deployment_group.id})

    _device_outside_group = Fixtures.device_fixture(org, product, firmware)

    conn = get(conn, ~p"/org/#{org}/#{product}/deployment_groups/#{deployment_group}/device_ids/download")

    [str] = Plug.Conn.get_resp_header(conn, "content-disposition")

    assert str =~ "attachment; filename"

    [header | rows] = NimbleCSV.RFC4180.parse_string(conn.resp_body, skip_headers: false)

    assert header == ["identifier"]
    assert rows == [[device_in_group.identifier]]
  end
end

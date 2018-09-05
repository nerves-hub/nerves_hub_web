defmodule NervesHubWWWWeb.DashboardControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser

  test "index", %{conn: conn} do
    conn = get(conn, dashboard_path(conn, :index))
    assert is_binary(html_response(conn, 200))
  end
end

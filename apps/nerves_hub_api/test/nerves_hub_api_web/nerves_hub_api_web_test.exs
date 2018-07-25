defmodule NervesHubAPIWebTest do
  use NervesHubAPIWeb.ConnCase

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  test "conn missing certificate is rejected", %{conn: conn} do
    conn = get conn, user_path(conn, :me)
    assert json_response(conn, 403)["status"] == "forbidden"
  end
end

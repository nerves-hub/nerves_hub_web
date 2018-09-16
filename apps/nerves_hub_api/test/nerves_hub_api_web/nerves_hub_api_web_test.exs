defmodule NervesHubAPIWebTest do
  use NervesHubAPIWeb.ConnCase, async: true

  test "conn missing certificate is rejected" do
    conn = Phoenix.ConnTest.build_conn()
    conn = get(conn, user_path(conn, :me))
    assert json_response(conn, 403)["status"] == "forbidden"
  end
end

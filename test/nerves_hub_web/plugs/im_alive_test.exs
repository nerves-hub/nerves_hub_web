defmodule NervesHubWeb.Plugs.ImAliveTest do
  use NervesHubWeb.ConnCase, async: true

  describe "GET /status/alive" do
    test "returns 200 OK when the database is reachable", %{conn: conn} do
      conn = get(conn, "/status/alive")
      assert conn.status == 200
      assert text_response(conn, 200) == "Hello, Friend!"
    end
  end
end

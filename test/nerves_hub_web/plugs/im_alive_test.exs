defmodule NervesHubWeb.Plugs.ImAliveTest do
  use NervesHubWeb.ConnCase, async: true

  alias NervesHubWeb.Plugs.ImAlive

  describe "GET /status/alive" do
    test "returns 200 OK when the database is reachable", %{conn: conn} do
      conn = get(conn, "/status/alive")
      assert conn.status == 200
      assert text_response(conn, 200) == "Hello, Friend!"
    end
  end

  describe "other /status/* paths" do
    test "GET /status/_health returns 200", %{conn: conn} do
      conn = get(conn, "/status/_health")
      assert conn.status == 200
    end

    test "GET /status/health returns 200", %{conn: conn} do
      conn = get(conn, "/status/health")
      assert conn.status == 200
    end

    test "GET /status/healthy returns 200", %{conn: conn} do
      conn = get(conn, "/status/healthy")
      assert conn.status == 200
    end
  end

  describe "with check_database: false" do
    test "answers on the status paths" do
      conn = %{build_conn(:get, "/status/alive") | request_path: "/status/alive"}
      result = ImAlive.call(conn, check_database: false)

      assert result.halted
      assert result.status == 200
      assert result.resp_body == "Hello, Friend!"
    end
  end

  describe "non-health-check paths" do
    test "passes the conn through untouched for non-status paths" do
      conn = %{build_conn(:get, "/some/other/path") | request_path: "/some/other/path"}
      result = ImAlive.call(conn, [])

      refute result.halted
    end
  end

  describe "status_path_spec/0" do
    test "returns a map keyed on the default status path" do
      spec = ImAlive.status_path_spec()
      assert is_map(spec)
      assert Map.has_key?(spec, "/status/alive")
    end
  end
end

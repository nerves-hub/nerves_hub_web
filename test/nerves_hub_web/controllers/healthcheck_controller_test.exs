defmodule NervesHubWeb.HealthcheckControllerTest do
  use NervesHubWeb.ConnCase, async: true

  describe "GET /healthcheck" do
    test "returns status and build information", %{conn: conn} do
      conn = get(conn, ~p"/healthcheck")
      response = json_response(conn, 200)
      assert response == %{"status" => "ok", "build" => System.build_info()[:revision]}
    end
  end
end

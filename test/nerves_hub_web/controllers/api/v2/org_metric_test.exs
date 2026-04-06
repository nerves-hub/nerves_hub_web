defmodule NervesHubWeb.API.V2.OrgMetricTest do
  use NervesHubWeb.AshAPIConnCase, async: false

  describe "index" do
    test "lists org metrics", %{conn: conn, org: org} do
      {:ok, _metric} =
        NervesHub.Accounts.create_org_metric(org.id, DateTime.utc_now(:second))

      conn = get(conn, "/api/v2/org-metrics")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
    end
  end

  describe "create" do
    test "creates an org metric", %{conn: conn, org: org} do
      timestamp = DateTime.utc_now(:second) |> DateTime.to_iso8601()

      conn =
        post(conn, "/api/v2/org-metrics", %{
          "data" => %{
            "type" => "org-metric",
            "attributes" => %{
              "org_id" => org.id,
              "devices" => 5,
              "bytes_stored" => 1024,
              "timestamp" => timestamp
            }
          }
        })

      resp = json_response(conn, 201)
      assert resp["data"]["attributes"]["devices"] == 5
      assert resp["data"]["attributes"]["bytes_stored"] == 1024
    end
  end
end

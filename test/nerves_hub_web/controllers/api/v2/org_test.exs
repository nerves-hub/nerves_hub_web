defmodule NervesHubWeb.API.V2.OrgTest do
  use NervesHubWeb.AshAPIConnCase, async: false

  alias NervesHub.Fixtures

  describe "index" do
    test "lists orgs", %{conn: conn, org: org} do
      conn = get(conn, "/api/v2/orgs")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      names = Enum.map(resp["data"], & &1["attributes"]["name"])
      assert org.name in names
    end
  end

  describe "create" do
    test "creates an org", %{conn: conn} do
      conn =
        post(conn, "/api/v2/orgs", %{
          "data" => %{
            "type" => "org",
            "attributes" => %{
              "name" => "ash-test-org"
            }
          }
        })

      resp = json_response(conn, 201)
      assert resp["data"]["attributes"]["name"] == "ash-test-org"
    end
  end

  describe "show" do
    test "returns an org by id", %{conn: conn, org: org} do
      conn = get(conn, "/api/v2/orgs/#{org.id}")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["name"] == org.name
    end
  end

  describe "update" do
    test "updates an org", %{conn: conn, org: org} do
      conn =
        patch(conn, "/api/v2/orgs/#{org.id}", %{
          "data" => %{
            "type" => "org",
            "id" => "#{org.id}",
            "attributes" => %{
              "name" => "updated-org-name"
            }
          }
        })

      resp = json_response(conn, 200)
      assert resp["data"]["attributes"]["name"] == "updated-org-name"
    end
  end

  describe "get_by_name" do
    test "returns an org by name", %{conn: conn, org: org} do
      conn = get(conn, "/api/v2/orgs/by-name/#{org.name}")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["name"] == org.name
    end
  end

  describe "get_for_user" do
    test "returns orgs for a user", %{conn: conn, org: org, user: user} do
      conn = get(conn, "/api/v2/orgs/for-user/#{user.id}")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      names = Enum.map(resp["data"], & &1["attributes"]["name"])
      assert org.name in names
    end
  end

  describe "delete" do
    test "soft-deletes an org", %{conn: conn, user: user} do
      org = Fixtures.org_fixture(user, %{name: "to-delete-org"})

      conn = delete(conn, "/api/v2/orgs/#{org.id}")
      assert response(conn, 200)
    end
  end
end

defmodule NervesHubWeb.API.V2.OrgKeyTest do
  use NervesHubWeb.AshAPIConnCase, async: false

  alias NervesHub.Fixtures

  describe "index" do
    test "lists org keys", %{conn: conn, org: org, user: user, tmp_dir: tmp_dir} do
      Fixtures.org_key_fixture(org, user, tmp_dir)

      conn = get(conn, "/api/v2/org-keys")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      assert length(resp["data"]) >= 1
    end
  end

  describe "create" do
    test "creates an org key", %{conn: conn, org: org, user: user} do
      conn =
        post(conn, "/api/v2/org-keys", %{
          "data" => %{
            "type" => "org-key",
            "attributes" => %{
              "name" => "ash-test-key",
              "key" => "a_test_key_value",
              "org_id" => org.id,
              "created_by_id" => user.id
            }
          }
        })

      resp = json_response(conn, 201)
      assert resp["data"]["attributes"]["name"] == "ash-test-key"
    end
  end

  describe "show" do
    test "returns an org key by id", %{conn: conn, org: org, user: user, tmp_dir: tmp_dir} do
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      conn = get(conn, "/api/v2/org-keys/#{org_key.id}")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["name"] == org_key.name
    end
  end

  describe "list_by_org" do
    test "lists org keys by org", %{conn: conn, org: org, user: user, tmp_dir: tmp_dir} do
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      conn = get(conn, "/api/v2/org-keys/by-org/#{org.id}")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      names = Enum.map(resp["data"], & &1["attributes"]["name"])
      assert org_key.name in names
    end
  end

  describe "get_by_name" do
    test "returns an org key by org and name", %{conn: conn, org: org, user: user, tmp_dir: tmp_dir} do
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      conn = get(conn, "/api/v2/org-keys/by-org/#{org.id}/by-name/#{org_key.name}")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["name"] == org_key.name
    end
  end

  describe "delete" do
    test "deletes an org key", %{conn: conn, org: org, user: user, tmp_dir: tmp_dir} do
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      conn = delete(conn, "/api/v2/org-keys/#{org_key.id}")
      assert response(conn, 200)
    end
  end
end

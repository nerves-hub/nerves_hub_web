defmodule NervesHubWeb.API.V2.OrgUserTest do
  use NervesHubWeb.AshAPIConnCase, async: false

  alias NervesHub.Fixtures

  describe "index" do
    test "lists org users", %{conn: conn} do
      conn = get(conn, "/api/v2/org-users")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      assert length(resp["data"]) >= 1
    end
  end

  describe "show" do
    test "returns an org user by id", %{conn: conn, org: org, user: user} do
      org_user = NervesHub.Repo.get_by!(NervesHub.Accounts.OrgUser, org_id: org.id, user_id: user.id)

      conn = get(conn, "/api/v2/org-users/#{org_user.id}")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["role"] == "admin"
    end
  end

  describe "create" do
    test "adds a user to an org", %{conn: conn, org: org} do
      new_user = Fixtures.user_fixture(%{name: "OrgUser Test", email: "orguser-test@test.com"})

      conn =
        post(conn, "/api/v2/org-users", %{
          "data" => %{
            "type" => "org-user",
            "attributes" => %{
              "org_id" => org.id,
              "user_id" => new_user.id,
              "role" => "view"
            }
          }
        })

      resp = json_response(conn, 201)
      assert resp["data"]["attributes"]["role"] == "view"
    end
  end

  describe "update" do
    test "updates an org user role", %{conn: conn, org: org, user: user} do
      new_user = Fixtures.user_fixture(%{name: "Role Update", email: "role-update@test.com"})
      {:ok, org_user} = NervesHub.Accounts.add_org_user(org, new_user, %{role: :view})

      conn =
        patch(conn, "/api/v2/org-users/#{org_user.id}", %{
          "data" => %{
            "type" => "org-user",
            "id" => "#{org_user.id}",
            "attributes" => %{
              "role" => "manage"
            }
          }
        })

      resp = json_response(conn, 200)
      assert resp["data"]["attributes"]["role"] == "manage"
    end
  end

  describe "list_by_org" do
    test "lists org users by org", %{conn: conn, org: org} do
      conn = get(conn, "/api/v2/org-users/by-org/#{org.id}")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      assert length(resp["data"]) >= 1
    end
  end

  describe "list_admins_by_org" do
    test "lists admin users by org", %{conn: conn, org: org} do
      conn = get(conn, "/api/v2/org-users/admins-by-org/#{org.id}")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      roles = Enum.map(resp["data"], & &1["attributes"]["role"])
      assert Enum.all?(roles, &(&1 == "admin"))
    end
  end

  describe "get_by_org_and_user" do
    test "returns an org user by org and user", %{conn: conn, org: org, user: user} do
      conn = get(conn, "/api/v2/org-users/by-org/#{org.id}/user/#{user.id}")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["role"] == "admin"
    end
  end

  describe "delete" do
    test "soft-deletes an org user", %{conn: conn, org: org} do
      new_user = Fixtures.user_fixture(%{name: "To Remove", email: "to-remove@test.com"})
      {:ok, org_user} = NervesHub.Accounts.add_org_user(org, new_user, %{role: :view})

      conn = delete(conn, "/api/v2/org-users/#{org_user.id}")
      assert response(conn, 200)
    end
  end
end

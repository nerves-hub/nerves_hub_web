defmodule NervesHubWeb.API.V2.InviteTest do
  use NervesHubWeb.AshAPIConnCase, async: false

  describe "index" do
    test "lists invites", %{conn: conn, org: org, user: user} do
      {:ok, _invite} =
        NervesHub.Accounts.invite(
          %{"email" => "invitee@test.com", "role" => "view"},
          org,
          user
        )

      conn = get(conn, "/api/v2/invites")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      emails = Enum.map(resp["data"], & &1["attributes"]["email"])
      assert "invitee@test.com" in emails
    end
  end

  describe "list_for_org" do
    test "lists invites for an org", %{conn: conn, org: org, user: user} do
      {:ok, _invite} =
        NervesHub.Accounts.invite(
          %{"email" => "org-invitee@test.com", "role" => "manage"},
          org,
          user
        )

      conn = get(conn, "/api/v2/invites/for-org/#{org.id}")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      emails = Enum.map(resp["data"], & &1["attributes"]["email"])
      assert "org-invitee@test.com" in emails
    end
  end

  describe "get_valid" do
    test "returns a valid invite by token", %{conn: conn, org: org, user: user} do
      {:ok, invite} =
        NervesHub.Accounts.invite(
          %{"email" => "valid@test.com", "role" => "view"},
          org,
          user
        )

      conn = get(conn, "/api/v2/invites/by-token/#{invite.token}")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["email"] == "valid@test.com"
    end
  end

  describe "create" do
    test "creates an invite", %{conn: conn, org: org, user: user} do
      conn =
        post(conn, "/api/v2/invites", %{
          "data" => %{
            "type" => "invite",
            "attributes" => %{
              "email" => "newinvite@test.com",
              "org_id" => org.id,
              "invited_by_id" => user.id,
              "role" => "view"
            }
          }
        })

      resp = json_response(conn, 201)
      assert resp["data"]["attributes"]["email"] == "newinvite@test.com"
      assert resp["data"]["attributes"]["token"] != nil
    end
  end

  describe "delete" do
    test "deletes an invite", %{conn: conn, org: org, user: user} do
      {:ok, invite} =
        NervesHub.Accounts.invite(
          %{"email" => "delete-me@test.com", "role" => "view"},
          org,
          user
        )

      conn = delete(conn, "/api/v2/invites/#{invite.id}")
      assert response(conn, 200)
    end
  end
end

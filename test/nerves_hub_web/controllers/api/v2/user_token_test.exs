defmodule NervesHubWeb.API.V2.UserTokenTest do
  use NervesHubWeb.AshAPIConnCase, async: false

  alias NervesHub.Accounts

  describe "index" do
    test "lists user tokens", %{conn: conn, user: user} do
      Accounts.create_user_api_token(user, "test-token")

      conn = get(conn, "/api/v2/user-tokens")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      assert length(resp["data"]) >= 1
    end
  end

  describe "show" do
    test "returns a user token by id", %{conn: conn, user: user} do
      encoded = Accounts.create_user_api_token(user, "show-test")
      {:ok, token} = Accounts.get_user_token(encoded)

      conn = get(conn, "/api/v2/user-tokens/#{token.id}")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["note"] == "show-test"
      assert resp["data"]["attributes"]["context"] == "api"
    end
  end

  describe "list_by_user" do
    test "lists api tokens for a user", %{conn: conn, user: user} do
      Accounts.create_user_api_token(user, "by-user-test")

      conn = get(conn, "/api/v2/user-tokens/by-user/#{user.id}")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      notes = Enum.map(resp["data"], & &1["attributes"]["note"])
      assert "by-user-test" in notes
    end
  end

  describe "create_api_token" do
    test "creates an api token", %{conn: conn, user: user} do
      conn =
        post(conn, "/api/v2/user-tokens", %{
          "data" => %{
            "type" => "user-token",
            "attributes" => %{
              "user_id" => user.id,
              "note" => "ash-api-token"
            }
          }
        })

      resp = json_response(conn, 201)
      assert resp["data"]["attributes"]["note"] == "ash-api-token"
      assert resp["data"]["attributes"]["context"] == "api"
    end
  end

  describe "delete" do
    test "deletes a user token", %{conn: conn, user: user} do
      encoded = Accounts.create_user_api_token(user, "to-delete")
      {:ok, token} = Accounts.get_user_token(encoded)

      conn = delete(conn, "/api/v2/user-tokens/#{token.id}")
      assert response(conn, 200)
    end
  end
end

defmodule NervesHubWeb.API.V2.UserTest do
  use NervesHubWeb.AshAPIConnCase, async: false

  describe "index" do
    test "lists users", %{conn: conn, user: user} do
      conn = get(conn, "/api/v2/users")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      emails = Enum.map(resp["data"], & &1["attributes"]["email"])
      assert user.email in emails
    end
  end

  describe "show" do
    test "returns a user by id", %{conn: conn, user: user} do
      conn = get(conn, "/api/v2/users/#{user.id}")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["email"] == user.email
    end
  end
end

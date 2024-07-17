defmodule NervesHubWeb.API.Plugs.UserTest do
  use ExUnit.Case, async: false
  use NervesHubWeb.APIConnCase

  test "can use API token auth", %{user: user, user_token: %{token: token}} do
    conn =
      build_conn()
      |> put_req_header("authorization", "token #{token}")
      |> put_req_header("accept", "application/json")
      |> get("/api/users/me")

    assert json_response(conn, 200)["data"] == %{
             "email" => user.email,
             "name" => user.name
           }

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("accept", "application/json")
      |> get("/api/users/me")

    assert json_response(conn, 200)["data"] == %{
             "email" => user.email,
             "name" => user.name
           }
  end

  test "rejects unknown API token" do
    assert_raise(NervesHubWeb.Unauthorized, fn ->
      build_conn()
      |> put_req_header("authorization", "token wat-is-this-token")
      |> put_req_header("accept", "application/json")
      |> get("/api/users/me")
    end)

    assert_raise(NervesHubWeb.Unauthorized, fn ->
      build_conn()
      |> put_req_header("authorization", "token nhu_1234567890abcdefghijklmnopqrstuvwxyz")
      |> put_req_header("accept", "application/json")
      |> get("/api/users/me")
    end)
  end
end

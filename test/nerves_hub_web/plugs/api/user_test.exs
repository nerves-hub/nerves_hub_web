defmodule NervesHubWeb.API.Plugs.UserTest do
  use ExUnit.Case, async: false
  use NervesHubWeb.APIConnCase

  setup do
    conn =
      build_conn()
      |> bypass_through(NervesHubWeb.API.Router)
      |> dispatch(NervesHubWeb.API.Endpoint, :get, "/users/me")

    %{conn: conn}
  end

  test "can use API token auth", %{user: user, user_token: %{token: token}} do
    conn =
      build_conn()
      |> put_req_header("authorization", "token #{token}")
      |> put_req_header("accept", "application/json")
      |> get("/users/me")

    assert json_response(conn, 200)["data"] == %{
             "email" => user.email,
             "username" => user.username
           }

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("accept", "application/json")
      |> get("/users/me")

    assert json_response(conn, 200)["data"] == %{
             "email" => user.email,
             "username" => user.username
           }
  end

  test "rejects unknown API token" do
    conn =
      build_conn()
      |> put_req_header("authorization", "token wat-is-this-token")
      |> put_req_header("accept", "application/json")
      |> get("/users/me")

    conn2 =
      build_conn()
      |> put_req_header("authorization", "token nhu_1234567890abcdefghijklmnopqrstuvwxyz")
      |> put_req_header("accept", "application/json")
      |> get("/users/me")

    assert json_response(conn, 403)
    assert json_response(conn2, 403)
  end
end

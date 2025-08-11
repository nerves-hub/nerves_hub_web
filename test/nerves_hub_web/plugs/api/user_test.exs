defmodule NervesHubWeb.API.Plugs.UserTest do
  use ExUnit.Case, async: false
  use NervesHubWeb.APIConnCase

  alias NervesHub.Accounts
  alias NervesHub.Repo
  alias NervesHub.Support.Utils

  test "can use API token auth", %{user: user, user_token: token} do
    {:ok, user_token} = Accounts.get_user_token(token)

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

    assert user_token.last_used != Repo.reload!(user_token).last_used
  end

  test "can use V1 API token auth", %{user: user} do
    user_token = Utils.create_v1_user_token!(user)

    conn =
      build_conn()
      |> put_req_header("authorization", "token #{user_token.old_token}")
      |> put_req_header("accept", "application/json")
      |> get("/api/users/me")

    assert json_response(conn, 200)["data"] == %{
             "email" => user.email,
             "name" => user.name
           }

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{user_token.old_token}")
      |> put_req_header("accept", "application/json")
      |> get("/api/users/me")

    assert json_response(conn, 200)["data"] == %{
             "email" => user.email,
             "name" => user.name
           }

    assert user_token.last_used != Repo.reload!(user_token).last_used
  end

  test "rejects unknown API token" do
    assert_raise(NervesHubWeb.UnauthorizedError, fn ->
      build_conn()
      |> put_req_header("authorization", "token wat-is-this-token")
      |> put_req_header("accept", "application/json")
      |> get("/api/users/me")
    end)

    assert_raise(NervesHubWeb.UnauthorizedError, fn ->
      build_conn()
      |> put_req_header("authorization", "token nhu_1234567890abcdefghijklmnopqrstuvwxyz")
      |> put_req_header("accept", "application/json")
      |> get("/api/users/me")
    end)
  end

  test "rejects improperly formatted API token" do
    assert_raise(NervesHubWeb.UnauthorizedError, fn ->
      build_conn()
      |> put_req_header("authorization", "asdf")
      |> put_req_header("accept", "application/json")
      |> get("/api/users/me")
    end)

    assert_raise(NervesHubWeb.UnauthorizedError, fn ->
      build_conn()
      |> put_req_header("authorization", "token")
      |> put_req_header("accept", "application/json")
      |> get("/api/users/me")
    end)
  end
end

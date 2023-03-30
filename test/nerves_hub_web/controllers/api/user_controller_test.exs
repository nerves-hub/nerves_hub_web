defmodule NervesHubWeb.API.UserControllerTest do
  use NervesHubWeb.APIConnCase, async: true

  alias NervesHub.Fixtures

  test "me", %{conn: conn, user: user} do
    conn = get(conn, Routes.user_path(conn, :me))

    assert json_response(conn, 200)["data"] == %{
             "username" => user.username,
             "email" => user.email
           }
  end

  test "authenticate existing accounts" do
    password = "12345678"

    user =
      Fixtures.user_fixture(%{
        username: "new_user",
        email: "account_test@test.com",
        password: password
      })

    conn = build_conn()
    conn = post(conn, Routes.user_path(conn, :auth), %{email: user.email, password: password})

    assert json_response(conn, 200)["data"] == %{
             "username" => user.username,
             "email" => user.email
           }
  end

  test "create token for existing account when authenticated" do
    password = "12345678"

    user =
      Fixtures.user_fixture(%{
        username: "new_user",
        email: "account_test@test.com",
        password: password
      })

    conn = build_conn()

    conn =
      post(conn, Routes.user_path(conn, :login), %{
        email: user.email,
        password: password,
        note: "tester"
      })

    resp = json_response(conn, 200)
    assert resp["data"]["username"] == user.username
    assert resp["data"]["email"] == user.email
    assert "nhu_" <> _ = resp["data"]["token"]
  end

  test "authenticate existing accounts with username instead of email" do
    password = "12345678"

    user =
      Fixtures.user_fixture(%{
        username: "new_user",
        email: "account_test@test.com",
        password: password
      })

    conn = build_conn()

    conn =
      post(conn, Routes.user_path(conn, :auth), %{username: user.username, password: password})

    assert json_response(conn, 200)["data"] == %{
             "username" => user.username,
             "email" => user.email
           }
  end
end

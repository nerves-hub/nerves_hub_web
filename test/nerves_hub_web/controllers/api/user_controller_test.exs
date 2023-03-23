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

  describe "register new account" do
    test "register new account" do
      conn = build_conn()
      body = %{username: "api_test", password: "12345678", email: "new_test@test.com"}
      conn = post(conn, Routes.user_path(conn, :register), body)

      assert json_response(conn, 200)["data"] == %{
               "username" => body.username,
               "email" => body.email
             }
    end

    test "shows an error when username/org doesn't conform to ~r/^[A-Za-z0-9-_]" do
      conn = build_conn()
      body = %{username: "api.test", password: "12345678", email: "new_test@test.com"}
      conn = post(conn, Routes.user_path(conn, :register), body)

      assert json_response(conn, 422) == %{
               "errors" => %{"username" => ["invalid character(s) in username"]}
             }
    end
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

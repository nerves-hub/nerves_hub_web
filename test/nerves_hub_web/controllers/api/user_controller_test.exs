defmodule NervesHubWeb.API.UserControllerTest do
  use NervesHubWeb.APIConnCase, async: true

  alias NervesHub.Fixtures

  test "me", %{conn: conn, user: user} do
    conn = get(conn, Routes.api_user_path(conn, :me))

    assert json_response(conn, 200)["data"] == %{
             "email" => user.email,
             "name" => user.name
           }
  end

  test "authenticate existing accounts" do
    password = "1234567891011"

    user =
      Fixtures.user_fixture(%{
        email: "account_test@test.com",
        name: "New User",
        password: password
      })

    conn = build_conn()
    conn = post(conn, Routes.api_user_path(conn, :auth), %{email: user.email, password: password})

    assert json_response(conn, 200)["data"] == %{
             "email" => user.email,
             "name" => user.name
           }
  end

  test "create token for existing account when authenticated" do
    password = "1234567891011"

    user =
      Fixtures.user_fixture(%{
        email: "account_test@test.com",
        name: "New User",
        password: password
      })

    conn = build_conn()

    conn =
      post(conn, Routes.api_user_path(conn, :login), %{
        email: user.email,
        note: "tester",
        password: password
      })

    resp = json_response(conn, 200)
    assert resp["data"]["name"] == user.name
    assert resp["data"]["email"] == user.email
    assert "nhu_" <> _ = resp["data"]["token"]
  end
end

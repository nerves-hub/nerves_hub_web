defmodule NervesHubWeb.API.UserControllerTest do
  use NervesHubWeb.APIConnCase, async: true

  alias NervesHub.Fixtures
  alias NervesHub.Repo

  test "me", %{conn: conn, user: user} do
    conn = get(conn, Routes.api_user_path(conn, :me))

    assert json_response(conn, 200)["data"] == %{
             "name" => user.name,
             "email" => user.email
           }
  end

  test "authenticate existing accounts" do
    password = "1234567891011"

    user =
      Fixtures.user_fixture(%{
        name: "New User",
        email: "account_test@test.com",
        password: password
      })

    conn = build_conn()
    conn = post(conn, Routes.api_user_path(conn, :auth), %{email: user.email, password: password})

    assert json_response(conn, 200)["data"] == %{
             "name" => user.name,
             "email" => user.email
           }
  end

  test "authentication shouldn't blow up if the password isn't included" do
    user =
      Fixtures.user_fixture(%{
        name: "New User",
        email: "account_test@test.com",
        password: "1234567891011"
      })

    conn = build_conn()
    conn = post(conn, Routes.api_user_path(conn, :auth), %{email: user.email})

    assert json_response(conn, 401)["errors"] == %{
             "detail" => "Authentication failed, please check your username and password and try again."
           }
  end

  test "authentication shouldn't blow up if the password is nil" do
    user =
      Fixtures.user_fixture(%{
        name: "New User",
        email: "account_test@test.com",
        password: "1234567891011"
      })

    conn = build_conn()
    conn = post(conn, Routes.api_user_path(conn, :auth), %{email: user.email, password: nil})

    assert json_response(conn, 401)["errors"] == %{
             "detail" => "Authentication failed, please check your username and password and try again."
           }
  end

  test "authentication shouldn't blow up if the password hash is nil" do
    user =
      Fixtures.user_fixture(%{
        name: "New User",
        email: "account_test@test.com",
        password: "1234567891011"
      })

    user = Repo.update!(Ecto.Changeset.change(user, password_hash: nil))

    conn = build_conn()
    conn = post(conn, Routes.api_user_path(conn, :auth), %{email: user.email, password: "1234567891011"})

    assert json_response(conn, 401)["errors"] == %{
             "detail" => "Authentication failed, please check your username and password and try again."
           }
  end

  test "create token for existing account when authenticated" do
    password = "1234567891011"

    user =
      Fixtures.user_fixture(%{
        name: "New User",
        email: "account_test@test.com",
        password: password
      })

    conn = build_conn()

    conn =
      post(conn, Routes.api_user_path(conn, :login), %{
        email: user.email,
        password: password,
        note: "tester"
      })

    resp = json_response(conn, 200)
    assert resp["data"]["name"] == user.name
    assert resp["data"]["email"] == user.email
    assert "nhu_" <> _ = resp["data"]["token"]
  end
end

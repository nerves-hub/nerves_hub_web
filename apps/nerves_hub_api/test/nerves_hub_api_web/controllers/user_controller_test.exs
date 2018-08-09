defmodule NervesHubAPIWeb.UserControllerTest do
  use NervesHubAPIWeb.ConnCase

  test "me", %{conn: conn, user: user} do
    conn = get(conn, user_path(conn, :me))

    assert json_response(conn, 200)["data"] == %{
             "name" => user.name,
             "email" => user.email
           }
  end

  test "register new account", %{} do
    conn = build_conn()
    body = %{name: "test", password: "12345678", email: "test@test.com"}
    conn = post(conn, user_path(conn, :register), body)

    assert json_response(conn, 200)["data"] == %{
             "name" => body.name,
             "email" => body.email
           }
  end
end

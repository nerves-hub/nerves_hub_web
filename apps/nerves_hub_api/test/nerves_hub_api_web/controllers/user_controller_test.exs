defmodule NervesHubAPIWeb.UserControllerTest do
  use NervesHubAPIWeb.ConnCase, async: true

  alias NervesHubCore.Fixtures
  alias NervesHubCore.Certificate
  alias NervesHubCore.Accounts

  test "me", %{conn: conn, user: user} do
    conn = get(conn, user_path(conn, :me))

    assert json_response(conn, 200)["data"] == %{
             "username" => user.username,
             "email" => user.email
           }
  end

  test "register new account" do
    conn = build_conn()
    body = %{username: "api_test", password: "12345678", email: "new_test@test.com"}
    conn = post(conn, user_path(conn, :register), body)

    assert json_response(conn, 200)["data"] == %{
             "username" => body.username,
             "email" => body.email
           }
  end

  test "authenticate existing accounts" do
    password = "12345678"
    org = Fixtures.org_fixture(%{name: "a new name"})

    user =
      Fixtures.user_fixture(%{
        orgs: [org],
        username: "new_user",
        email: "account_test@test.com",
        password: password
      })

    conn = build_conn()
    conn = post(conn, user_path(conn, :auth), %{email: user.email, password: password})

    assert json_response(conn, 200)["data"] == %{
             "username" => user.username,
             "email" => user.email
           }
  end

  @tag :ca_integration
  test "sign new registration certificates" do
    csr =
      Fixtures.path()
      |> Path.join("cfssl/user-csr.pem")
      |> File.read!()
      |> Base.encode64()

    params =
      Fixtures.user_fixture()
      |> Map.take([:email, :password])
      |> Map.put(:csr, csr)
      |> Map.put(:description, "test-machine")

    conn = build_conn()

    conn = post(conn, user_path(conn, :sign), params)
    resp_data = json_response(conn, 200)["data"]
    assert %{"cert" => cert} = resp_data

    {:ok, serial} = Certificate.get_serial_number(cert)

    user = Accounts.get_user_by_certificate_serial(serial)
    assert user.email == params.email
  end
end

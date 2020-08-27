defmodule NervesHubAPIWeb.UserControllerTest do
  use NervesHubAPIWeb.ConnCase, async: true

  alias NervesHubWebCore.Fixtures
  alias NervesHubWebCore.Certificate
  alias NervesHubWebCore.Accounts

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

      assert json_response(conn, 422) == %{"errors" => %{"username" => ["invalid character(s) in username"]}}
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

  @tag :ca_integration
  test "sign new registration certificates" do
    subject = "/O=NervesHub/CN=username"
    key = X509.PrivateKey.new_ec(:secp256r1)

    csr =
      X509.CSR.new(key, subject)
      |> X509.CSR.to_pem()
      |> Base.encode64()

    params =
      Fixtures.user_fixture(name: "username")
      |> Map.take([:email, :password])
      |> Map.put(:csr, csr)
      |> Map.put(:description, "test-machine")

    conn = build_conn()

    conn = post(conn, Routes.user_path(conn, :sign), params)
    resp_data = json_response(conn, 200)["data"]
    assert %{"cert" => cert} = resp_data

    cert = X509.Certificate.from_pem!(cert)
    serial = Certificate.get_serial_number(cert)

    user = Accounts.get_user_by_certificate_serial(serial)
    assert user.email == params.email
  end
end

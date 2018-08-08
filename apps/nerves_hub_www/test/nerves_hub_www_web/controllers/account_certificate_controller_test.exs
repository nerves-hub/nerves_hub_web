defmodule NervesHubWWWWeb.AccountCertificateControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser

  alias NervesHubCore.Fixtures
  alias NervesHubCore.Accounts

  @create_attrs %{
    description: "test cert",
    serial: "1580653878678601091983566405937658689714637"
  }

  describe "index" do
    test "lists all appropriate account certificates", %{
      conn: conn,
      current_org: org,
      current_user: user
    } do
      foo_cert = Fixtures.user_certificate_fixture(user, %{description: "foo", serial: "abc123"})
      bar_cert = Fixtures.user_certificate_fixture(user, %{description: "bar", serial: "321cba"})

      other_user = Fixtures.user_fixture(org, %{email: "test@email.com"})

      Fixtures.user_certificate_fixture(other_user, %{description: "baz", serial: "anotherserial"})

      conn = get(conn, account_certificate_path(conn, :index))
      assert html_response(conn, 200) =~ "Account Certificates"
      assert html_response(conn, 200) =~ account_certificate_path(conn, :delete, foo_cert)
      assert html_response(conn, 200) =~ account_certificate_path(conn, :delete, bar_cert)
      refute html_response(conn, 200) =~ "baz"
    end
  end

  describe "new certificate" do
    test "renders form", %{conn: conn} do
      conn = get(conn, account_certificate_path(conn, :new))
      assert html_response(conn, 200) =~ "Generate an Account Certificate"
    end
  end

  @tag :ca_integration
  describe "create product" do
    test "redirects to show when data is valid", %{conn: conn} do
      conn = post(conn, account_certificate_path(conn, :create), user_certificate: @create_attrs)

      assert %{id: id} = redirected_params(conn)
      assert redirected_to(conn) =~ account_certificate_path(conn, :show, id)

      conn = get(conn, account_certificate_path(conn, :show, id))
      assert html_response(conn, 200) =~ "User Certificate"
    end
  end

  describe "delete user_certificate" do
    test "deletes chosen certificate", %{conn: conn, current_user: user} do
      [cert | _] = Accounts.get_user_certificates(user)
      conn = delete(conn, account_certificate_path(conn, :delete, cert))
      assert redirected_to(conn) == account_certificate_path(conn, :index)

      assert_error_sent(404, fn ->
        get(conn, product_path(conn, :show, cert))
      end)
    end
  end
end

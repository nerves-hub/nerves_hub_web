defmodule NervesHubWWWWeb.SessionControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: true

  alias NervesHubWebCore.Fixtures

  setup do
    user =
      Fixtures.user_fixture(%{
        name: "Foo Bar",
        email: "foo@bar.com",
        password: "password"
      })

    org = Fixtures.org_fixture(user, %{name: "my_test_org_1"})
    {:ok, %{user: user, org: org}}
  end

  describe "new session" do
    test "renders form" do
      conn = build_conn()
      conn = get(conn, Routes.session_path(conn, :new))
      assert html_response(conn, 200) =~ "Log in to your NervesHub account"
    end
  end

  describe "create session" do
    test "redirected to product when logging in", %{user: user} do
      conn = build_conn()

      conn =
        post(
          conn,
          Routes.session_path(conn, :create),
          login: %{email_or_username: user.email, password: user.password}
        )

      assert redirected_to(conn) == Routes.product_path(conn, :index, user.username)
    end

    test "redirected to original URL when logging in", %{user: user} do
      conn = build_conn(:get, "/org/new")
      conn = get(conn, Routes.org_path(conn, :new))

      conn =
        post(
          conn,
          Routes.session_path(conn, :create),
          login: %{email_or_username: user.email, password: user.password}
        )

      assert redirected_to(conn) == Routes.org_path(conn, :new)
    end
  end
end

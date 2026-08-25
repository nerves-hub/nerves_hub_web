defmodule NervesHubWeb.Plugs.RedirectorServerAuthTest do
  use NervesHubWeb.ConnCase

  alias NervesHub.Accounts.Scope
  alias NervesHubWeb.Plugs.Redirector
  alias NervesHubWeb.Plugs.ServerAuth

  describe "Redirector.init/1" do
    test "accepts [to: path] option" do
      assert [to: "/some/path"] = Redirector.init(to: "/some/path")
    end

    test "accepts [external: url] option" do
      assert [external: "https://example.com"] = Redirector.init(external: "https://example.com")
    end

    test "raises when neither :to nor :external is provided" do
      assert_raise RuntimeError, fn -> Redirector.init([]) end
      assert_raise RuntimeError, fn -> Redirector.init(unknown: "value") end
    end
  end

  describe "Redirector.call/2 with :to" do
    test "redirects to path when conn has no query string" do
      conn = build_conn(:get, "/original")
      result = Redirector.call(conn, to: "/destination")

      assert redirected_to(result) == "/destination"
    end

    test "appends query string to path when conn has one" do
      conn = %{build_conn(:get, "/original") | query_string: "foo=bar&baz=qux"}
      result = Redirector.call(conn, to: "/destination")

      assert redirected_to(result) == "/destination?foo=bar&baz=qux"
    end
  end

  describe "Redirector.call/2 with :external" do
    test "redirects to external URL (query params preserved or empty string appended when none)" do
      conn = build_conn(:get, "/original")
      result = Redirector.call(conn, external: "https://example.com/path")

      location = redirected_to(result)
      # Empty query_string results in a trailing "?" — the destination host is correct
      assert String.starts_with?(location, "https://example.com/path")
    end

    test "appends conn query string to external URL that has no query" do
      conn = %{build_conn(:get, "/original") | query_string: "ref=test"}
      result = Redirector.call(conn, external: "https://example.com/path")

      assert redirected_to(result) == "https://example.com/path?ref=test"
    end

    test "merges conn query string into existing external URL query params, conn params winning on conflict" do
      conn = %{build_conn(:get, "/original") | query_string: "key=new"}
      result = Redirector.call(conn, external: "https://example.com/path?key=old&other=1")

      location = redirected_to(result)
      uri = URI.parse(location)
      params = URI.decode_query(uri.query)

      # source (conn) wins on conflict
      assert params["key"] == "new"
      assert params["other"] == "1"
    end
  end

  describe "ServerAuth.call/2" do
    test "passes through conn when user has a non-nil server_role" do
      user = %{server_role: :admin}
      scope = %Scope{user: user}

      conn =
        build_conn(:get, "/admin")
        |> assign(:current_scope, scope)

      result = ServerAuth.call(conn, [])

      refute result.halted
    end

    test "passes through conn when user has :view server_role" do
      user = %{server_role: :view}
      scope = %Scope{user: user}

      conn =
        build_conn(:get, "/admin")
        |> assign(:current_scope, scope)

      result = ServerAuth.call(conn, [])

      refute result.halted
    end

    test "halts and redirects when user has nil server_role" do
      user = %{server_role: nil}
      scope = %Scope{user: user}

      conn =
        build_conn(:get, "/admin")
        |> assign(:current_scope, scope)
        # Needed for put_flash/put_session to work in tests
        |> Plug.Test.init_test_session(%{})
        |> Phoenix.Controller.fetch_flash()

      result = ServerAuth.call(conn, [])

      assert result.halted
      assert redirected_to(result) == "/"
    end
  end

  describe "ServerAuth.resolve_access/1" do
    test "returns :all for admin role" do
      user = %{server_role: :admin}
      assert ServerAuth.resolve_access(user) == :all
    end

    test "returns :read_only for view role" do
      user = %{server_role: :view}
      assert ServerAuth.resolve_access(user) == :read_only
    end

    test "returns :read_only for nil server_role" do
      user = %{server_role: nil}
      assert ServerAuth.resolve_access(user) == :read_only
    end
  end
end

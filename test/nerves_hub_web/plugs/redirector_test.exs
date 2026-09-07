defmodule NervesHubWeb.Plugs.RedirectorTest do
  use NervesHubWeb.ConnCase, async: true

  alias NervesHubWeb.Plugs.Redirector

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

      assert params["key"] == "new"
      assert params["other"] == "1"
    end
  end
end

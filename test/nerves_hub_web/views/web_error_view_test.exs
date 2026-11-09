defmodule NervesHubWeb.WebErrorViewTest do
  use NervesHubWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  defp render_error(template, conn \\ nil) do
    assigns = if conn, do: [conn: conn], else: []
    render_to_string(NervesHubWeb.ErrorHTML, template, "html", assigns)
  end

  defp failed_request(method, path) do
    method
    |> Phoenix.ConnTest.build_conn(path)
    |> Plug.Conn.put_resp_header("x-request-id", "F7c2a91e4b0d83a6")
  end

  describe "404" do
    test "names the two likely causes and shows the path that was asked for" do
      html = render_error("404", failed_request(:get, "/org/acme/devices/nh-0042"))

      assert html =~ "<title>Page not found · NervesHub</title>"
      assert html =~ "That page doesn’t exist,"
      assert html =~ "or you don’t have access."
      assert html =~ "/<wbr>org/<wbr>acme/<wbr>devices/<wbr>nh-0042"
      assert html =~ ~s(href="/orgs")
      assert html =~ "Go back"
    end

    test "escapes the path" do
      html = render_error("404", failed_request(:get, "/org/<script>alert(1)</script>"))

      assert html =~ "&lt;script&gt;alert(1)&lt;"
      refute html =~ "<script>alert(1)"
    end

    test "still reads without a conn" do
      assert render_error("404") =~ "Nothing at this address is visible to your account."
    end
  end

  describe "500" do
    test "offers a retry for a GET and shows the request ID" do
      html = render_error("500", failed_request(:get, "/org/acme"))

      assert html =~ "<title>Unexpected error · NervesHub</title>"
      assert html =~ "Something on our side blew a fuse."
      assert html =~ "Try again"
      refute html =~ "Go back"
      assert html =~ ~s(<code id="request-id")
      assert html =~ "F7c2a91e4b0d83a6"
    end

    test "offers going back instead of a retry for anything but a GET" do
      html = render_error("500", failed_request(:post, "/org/acme"))

      refute html =~ "Try again"
      assert html =~ "Go back"
    end

    test "has no status button when the instance has no status page" do
      refute render_error("500") =~ "Check status"
    end
  end

  test "render 400.html" do
    html = render_error("400", failed_request(:post, "/login"))

    assert html =~ "<title>Invalid request · NervesHub</title>"
    assert html =~ "We couldn’t read that request."
    assert html =~ "F7c2a91e4b0d83a6"
  end

  test "every error page renders the logo" do
    for template <- ["400", "404", "500"] do
      html = render_error(template)

      refute html =~ "product.svg"
      assert html =~ ~s(fill="#6366F1")
    end
  end
end

defmodule NervesHubWWWWeb.PolicyControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: true

  describe "policies" do
    test "renders terms of service", %{
      conn: conn
    } do
      conn = get(conn, policy_path(conn, :tos))
      assert html_response(conn, 200) =~ "Terms of Service"
    end

    test "renders code of conduct", %{
      conn: conn
    } do
      conn = get(conn, policy_path(conn, :coc))
      assert html_response(conn, 200) =~ "Code of Conduct"
    end

    test "renders privacy policy", %{
      conn: conn
    } do
      conn = get(conn, policy_path(conn, :privacy))
      assert html_response(conn, 200) =~ "Privacy Policy"
    end
  end
end

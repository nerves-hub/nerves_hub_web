defmodule NervesHubWWWWeb.OrgUserControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: true

  alias NervesHubWebCore.Accounts

  describe "index" do
    test "lists all users in an organization", %{
      conn: conn,
      current_org: org
    } do
      org_users = Accounts.get_org_users(org)
      conn = get(conn, org_user_path(conn, :index))
      assert html_response(conn, 200) =~ "#{org.name} Users"

      Enum.each(org_users, fn org_user ->
        assert html_response(conn, 200) =~ org_user.user.username
      end)
    end
  end
end

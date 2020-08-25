defmodule NervesHubWWWWeb.OrgUserControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: true

  alias NervesHubWebCore.Accounts

  describe "index" do
    test "lists all users in an organization", %{
      conn: conn,
      org: org
    } do
      org_users = Accounts.get_org_users(org)
      conn = get(conn, Routes.org_user_path(conn, :index, org.name))
      assert html_response(conn, 200) =~ "Users"

      Enum.each(org_users, fn org_user ->
        assert html_response(conn, 200) =~ org_user.user.username
      end)
    end

    test "user is able to invite users to org", %{conn: conn, org: org} do
      conn = get(conn, Routes.org_user_path(conn, :index, org.name))
      assert html_response(conn, 200) =~ "Add New User"
    end

    test "user is unable to invite users to user org", %{conn: conn, user: user} do
      conn = get(conn, Routes.org_user_path(conn, :index, user.username))
      refute html_response(conn, 200) =~ "Add New User"
    end
  end
end

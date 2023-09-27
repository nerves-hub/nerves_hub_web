defmodule NervesHubWeb.OrgUserControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  import Swoosh.TestAssertions

  alias NervesHub.{Accounts, Fixtures}

  setup context do
    user = Fixtures.user_fixture(%{username: context.user.username <> "0"})
    Map.put(context, :user2, user)
  end

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
  end

  describe "update org_user role" do
    setup [:create_org_user]

    test "updates role and redirects", %{conn: conn, org: org, user2: user} do
      conn =
        put(conn, Routes.org_user_path(conn, :update, org.name, user.id), %{
          org_user: %{role: "write"}
        })

      assert redirected_to(conn) == Routes.org_user_path(conn, :index, org.name)

      conn = get(conn, Routes.org_user_path(conn, :index, org.name))
      assert html_response(conn, 200) =~ "Role updated"
      assert html_response(conn, 200) =~ "write"
    end

    test "shows error", %{conn: conn, org: org, user2: user} do
      conn =
        put(conn, Routes.org_user_path(conn, :update, org.name, user.id), %{
          org_user: %{role: "invalid role"}
        })

      assert html_response(conn, 200) =~ "Error updating role"
      assert html_response(conn, 200) =~ "is invalid"
    end
  end

  describe "delete valid user" do
    setup [:create_org_user]

    test "removes existing user", %{conn: conn, org: org, user2: user} do
      conn = delete(conn, Routes.org_user_path(conn, :delete, org.name, user.id))
      assert redirected_to(conn) == Routes.org_user_path(conn, :index, org.name)

      # An email should have been sent
      instigator = conn.assigns.user.username

      assert_email_sent(
        subject: "[NervesHub] User #{instigator} removed #{user.username} from #{org.name}"
      )

      assert {:error, :not_found} = Accounts.get_org_user(org, user)

      conn = get(conn, Routes.org_user_path(conn, :index, org.name))
      assert html_response(conn, 200) =~ "User removed"
    end
  end

  describe "delete invalid user" do
    test "fails to remove existing user", %{conn: conn, org: org, user: user} do
      {:ok, org_user} = Accounts.get_org_user(org, user)
      conn = delete(conn, Routes.org_user_path(conn, :delete, org.name, user.id))
      assert redirected_to(conn) == Routes.org_user_path(conn, :index, org.name)

      refute_email_sent()

      assert {:ok, ^org_user} = Accounts.get_org_user(org, user)

      conn = get(conn, Routes.org_user_path(conn, :index, org.name))
      assert html_response(conn, 200) =~ "Could not remove user"
    end
  end

  defp create_org_user(%{user2: user, org: org}) do
    {:ok, org_user} = Accounts.add_org_user(org, user, %{role: :admin})
    {:ok, %{org_user: org_user}}
  end
end

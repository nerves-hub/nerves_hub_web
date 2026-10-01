defmodule NervesHubWeb.API.OrgUserControllerTest do
  use NervesHubWeb.APIConnCase, async: true

  import NervesHub.Support.Emails
  import Swoosh.TestAssertions

  alias NervesHub.Accounts
  alias NervesHub.Fixtures

  setup context do
    org = Fixtures.org_fixture(context.user, %{name: "api_test"})
    Map.put(context, :org, org)
  end

  describe "index" do
    test "lists all org_users", %{conn: conn, org: org, user: user} do
      conn = get(conn, Routes.api_org_user_path(conn, :index, org.name))

      assert json_response(conn, 200)["data"] ==
               [%{"email" => user.email, "role" => "admin", "custom_role" => nil, "name" => user.name}]
    end

    test "names the custom role of a member who holds one", %{conn: conn, org: org} do
      role = Fixtures.org_role_fixture(org, %{name: "Release Manager"})
      member = Fixtures.user_fixture()
      {:ok, _} = Accounts.add_org_user(org, member, %{org_role_id: role.id})

      conn = get(conn, Routes.api_org_user_path(conn, :index, org.name))

      assert %{"role" => nil, "custom_role" => "Release Manager"} =
               Enum.find(json_response(conn, 200)["data"], &(&1["email"] == member.email))
    end

    test "any member can list the org's members", %{conn2: conn, org: org, user2: user} do
      for role <- [%{role: :manage}, %{role: :view}, %{org_role_id: Fixtures.org_role_fixture(org).id}] do
        {:ok, org_user} = Accounts.add_org_user(org, user, role)

        emails =
          conn
          |> get(Routes.api_org_user_path(conn, :index, org.name))
          |> json_response(200)
          |> get_in(["data", Access.all(), "email"])

        assert user.email in emails

        :ok = Accounts.soft_delete_org_user(org_user)
      end
    end
  end

  describe "show" do
    test "view member details", %{conn: conn, org: org, user: user} do
      conn = get(conn, Routes.api_org_user_path(conn, :show, org.name, user.email))

      assert json_response(conn, 200)["data"] ==
               %{"email" => user.email, "role" => "admin", "custom_role" => nil, "name" => user.name}
    end

    test "any member can view a member's details", %{conn2: conn, org: org, user: admin, user2: user} do
      {:ok, _} = Accounts.add_org_user(org, user, %{org_role_id: Fixtures.org_role_fixture(org).id})

      conn = get(conn, Routes.api_org_user_path(conn, :show, org.name, admin.email))

      assert %{"email" => email, "role" => "admin"} = json_response(conn, 200)["data"]
      assert email == admin.email
    end
  end

  describe "add user" do
    test "invites an existing user rather than adding them", %{conn: conn, org: org, user2: user2} do
      org_user = %{"email" => user2.email, "role" => "manage"}
      conn = post(conn, Routes.api_org_user_path(conn, :add, org.name), org_user)
      assert response(conn, 204)

      # they only become a member once they accept
      assert Accounts.get_org_user(org, user2) == {:error, :not_found}

      send_queued_emails()

      assert_email_sent(subject: "NervesHub: You have been invited to join #{org.name}")
    end

    test "renders errors when data is invalid", %{conn: conn, org: org, user2: user2} do
      org_user = %{"email" => user2.email, "role" => "bogus"}
      conn = post(conn, Routes.api_org_user_path(conn, :add, org.name), org_user)
      assert json_response(conn, 422)["errors"] != %{}
    end

    test "invites a user to the org if they don't have an account", %{conn: conn, org: org} do
      org_user = %{"email" => "bogus@example.com", "role" => "manage"}
      conn = post(conn, Routes.api_org_user_path(conn, :add, org.name), org_user)
      assert response(conn, 204)

      send_queued_emails()

      assert_email_sent()
    end

    for role <- [:manage, :view] do
      @role role

      test "error: user with #{@role} cannot add a user", %{conn2: conn, org: org, user2: user} do
        Accounts.add_org_user(org, user, %{role: @role})
        org_user = %{"username" => "1234", "role" => "admin"}

        assert_error_sent(401, fn ->
          post(conn, Routes.api_org_user_path(conn, :add, org.name), org_user)
        end)
        |> assert_authorization_error()
      end
    end
  end

  describe "invite user" do
    test "returns 400 when email or role are missing", %{conn: conn, org: org} do
      conn = post(conn, Routes.api_org_user_path(conn, :invite, org.name), %{})
      assert conn.status == 400
    end

    test "renders org_user when data is valid", %{conn: conn, org: org} do
      org_user = %{"email" => "bogus@example.com", "role" => "manage"}
      conn = post(conn, Routes.api_org_user_path(conn, :invite, org.name), org_user)
      assert response(conn, 204)

      send_queued_emails()

      assert_email_sent()
    end

    test "renders errors when role is invalid", %{conn: conn, org: org} do
      org_user = %{"email" => "bogus@example.com", "role" => "bogus"}

      conn = post(conn, Routes.api_org_user_path(conn, :invite, org.name), org_user)

      assert %{"role" => ["is invalid"]} = json_response(conn, 422)["errors"]
    end

    test "invites the user if they already have an account", %{conn: conn, org: org, user2: user2} do
      org_user = %{"email" => user2.email, "role" => "admin"}

      conn = post(conn, Routes.api_org_user_path(conn, :invite, org.name), org_user)

      assert response(conn, 204)
      assert Accounts.get_org_user(org, user2) == {:error, :not_found}
    end

    test "renders errors when the user is already a member", %{conn: conn, org: org, user2: user2} do
      {:ok, _org_user} = Accounts.add_org_user(org, user2, %{role: :view})

      org_user = %{"email" => user2.email, "role" => "manage"}
      conn = post(conn, Routes.api_org_user_path(conn, :invite, org.name), org_user)

      assert %{"email" => ["is already a member of this organization"]} =
               json_response(conn, 422)["errors"]
    end

    for role <- [:manage, :view] do
      @role role

      test "error: user with #{@role} cannot invite a user", %{conn2: conn, org: org, user2: user} do
        Accounts.add_org_user(org, user, %{role: @role})
        org_user = %{"username" => "1234", "role" => "admin"}

        assert_error_sent(401, fn ->
          post(conn, Routes.api_org_user_path(conn, :invite, org.name), org_user)
        end)
        |> assert_authorization_error()
      end
    end
  end

  describe "remove member" do
    test "remove existing user", %{conn: conn, org: org, user2: user} do
      Accounts.add_org_user(org, user, %{role: :admin})

      conn = delete(conn, Routes.api_org_user_path(conn, :remove, org.name, user.email))
      assert response(conn, 204)

      send_queued_emails()

      # don't send email to admin who added the user
      refute_email_sent()

      conn = get(conn, Routes.api_org_user_path(conn, :show, org.name, user.email))
      assert response(conn, 404)
    end

    for role <- [:manage, :view] do
      @role role

      test "error: user with #{@role} role cannot remove a member", %{conn2: conn, org: org, user2: user} do
        Accounts.add_org_user(org, user, %{role: @role})

        assert_error_sent(401, fn ->
          delete(conn, Routes.api_org_user_path(conn, :remove, org.name, "1234"))
        end)
        |> assert_authorization_error()
      end
    end
  end

  describe "update member role" do
    test "renders org_user when data is valid", %{conn: conn, org: org, user2: user} do
      Accounts.add_org_user(org, user, %{role: :admin})

      conn =
        put(conn, Routes.api_org_user_path(conn, :update, org.name, user.email), role: "manage")

      assert json_response(conn, 200)["data"]["role"] == "manage"

      path = Routes.api_org_user_path(conn, :show, org.name, user.email)
      conn = get(conn, path)
      assert json_response(conn, 200)["data"]["role"] == "manage"
    end

    for role <- [:manage, :view] do
      @role role

      test "error: user with #{@role} role cannot update a member's role", %{conn2: conn, org: org, user2: user} do
        Accounts.add_org_user(org, user, %{role: @role})

        assert_error_sent(401, fn ->
          put(conn, Routes.api_org_user_path(conn, :update, org.name, user.email), role: "manage")
        end)
        |> assert_authorization_error()
      end
    end
  end
end

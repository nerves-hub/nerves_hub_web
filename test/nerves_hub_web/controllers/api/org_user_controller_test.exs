defmodule NervesHubWeb.API.OrgUserControllerTest do
  use NervesHubWeb.APIConnCase, async: true

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
               [%{"email" => user.email, "role" => "admin", "name" => user.name}]
    end

    for role <- [:manage, :view] do
      @role role

      test "error: org #{@role} cannot list org members", %{conn2: conn, org: org, user2: user} do
        Accounts.add_org_user(org, user, %{role: @role})

        assert_error_sent(401, fn ->
          get(conn, Routes.api_org_user_path(conn, :index, org.name))
        end)
        |> assert_authorization_error()
      end
    end
  end

  describe "show" do
    test "view member details", %{conn: conn, org: org, user: user} do
      conn = get(conn, Routes.api_org_user_path(conn, :show, org.name, user.email))

      assert json_response(conn, 200)["data"] ==
               %{"email" => user.email, "role" => "admin", "name" => user.name}
    end

    for role <- [:manage, :view] do
      @role role

      test "error: org #{@role} cannot view member details", %{conn2: conn, org: org, user2: user} do
        Accounts.add_org_user(org, user, %{role: @role})

        assert_error_sent(401, fn ->
          get(conn, Routes.api_org_user_path(conn, :show, org.name, user.email))
        end)
        |> assert_authorization_error()
      end
    end
  end

  describe "add user" do
    test "renders org_user when data is valid", %{conn: conn, org: org, user2: user2} do
      org_user = %{"email" => user2.email, "role" => "manage"}
      conn = post(conn, Routes.api_org_user_path(conn, :add, org.name), org_user)
      assert json_response(conn, 201)["data"]

      conn = get(conn, Routes.api_org_user_path(conn, :show, org.name, user2.email))
      assert json_response(conn, 200)["data"]["name"] == user2.name

      # don't send email to admin who added the user
      refute_email_sent()
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
    test "renders org_user when data is valid", %{conn: conn, org: org} do
      org_user = %{"email" => "bogus@example.com", "role" => "manage"}
      conn = post(conn, Routes.api_org_user_path(conn, :invite, org.name), org_user)
      assert response(conn, 204)

      assert_email_sent()
    end

    test "renders errors when role is invalid", %{conn: conn, org: org} do
      org_user = %{"email" => "bogus@example.com", "role" => "bogus"}

      conn = post(conn, Routes.api_org_user_path(conn, :invite, org.name), org_user)

      assert %{"role" => ["is invalid"]} = json_response(conn, 422)["errors"]
    end

    test "add the user to the org if the user has an account", %{conn: conn, org: org, user2: user2} do
      org_user = %{"email" => user2.email, "role" => "admin"}

      conn = post(conn, Routes.api_org_user_path(conn, :invite, org.name), org_user)

      assert json_response(conn, 201)["data"]["name"] == user2.name
      assert json_response(conn, 201)["data"]["email"] == user2.email
      assert json_response(conn, 201)["data"]["role"] == "admin"
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

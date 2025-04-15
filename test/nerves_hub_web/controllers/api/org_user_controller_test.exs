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
  end

  describe "index roles" do
    for role <- [:manage, :view] do
      @role role

      test "error: org #{@role}", %{conn2: conn, org: org, user2: user} do
        Accounts.add_org_user(org, user, %{role: @role})

        assert_error_sent(401, fn ->
          get(conn, Routes.api_org_user_path(conn, :index, org.name))
        end)
        |> assert_authorization_error()
      end
    end
  end

  describe "add org_users" do
    test "renders org_user when data is valid", %{conn: conn, org: org, user2: user2} do
      org_user = %{"user_id" => user2.id, "role" => "manage"}
      conn = post(conn, Routes.api_org_user_path(conn, :add, org.name), org_user)
      assert json_response(conn, 201)["data"]

      conn = get(conn, Routes.api_org_user_path(conn, :show, org.name, user2.id))
      assert json_response(conn, 200)["data"]["name"] == user2.name

      assert_email_sent(subject: "NervesHub: #{user2.name} has been added to #{org.name}")
    end

    test "renders errors when data is invalid", %{conn: conn, org: org, user2: user2} do
      org_user = %{"user_id" => user2.id, "role" => "bogus"}
      conn = post(conn, Routes.api_org_user_path(conn, :add, org.name), org_user)
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "add role" do
    for role <- [:manage, :view] do
      @role role

      test "error: org #{@role}", %{conn2: conn, org: org, user2: user} do
        Accounts.add_org_user(org, user, %{role: @role})
        org_user = %{"username" => "1234", "role" => "admin"}

        assert_error_sent(401, fn ->
          post(conn, Routes.api_org_user_path(conn, :add, org.name), org_user)
        end)
        |> assert_authorization_error()
      end
    end
  end

  describe "remove org_user" do
    setup [:create_org_user]

    test "remove existing user", %{conn: conn, org: org, user2: user} do
      conn = delete(conn, Routes.api_org_user_path(conn, :remove, org.name, user.id))
      assert response(conn, 204)

      assert_email_sent(subject: "NervesHub: #{user.name} has been removed from #{org.name}")

      conn = get(conn, Routes.api_org_user_path(conn, :show, org.name, user.id))
      assert response(conn, 404)
    end
  end

  describe "remove role" do
    for role <- [:manage, :view] do
      @role role

      test "error: org #{@role}", %{conn2: conn, org: org, user2: user} do
        Accounts.add_org_user(org, user, %{role: @role})

        assert_error_sent(401, fn ->
          delete(conn, Routes.api_org_user_path(conn, :remove, org.name, "1234"))
        end)
        |> assert_authorization_error()
      end
    end
  end

  describe "update org_user role" do
    setup [:create_org_user]

    test "renders org_user when data is valid", %{conn: conn, org: org, user2: user} do
      conn =
        put(conn, Routes.api_org_user_path(conn, :update, org.name, user.id), role: "manage")

      assert json_response(conn, 200)["data"]["role"] == "manage"

      path = Routes.api_org_user_path(conn, :show, org.name, user.id)
      conn = get(conn, path)
      assert json_response(conn, 200)["data"]["role"] == "manage"
    end
  end

  describe "update role" do
    for role <- [:manage, :view] do
      @role role

      test "error: org #{@role}", %{conn2: conn, org: org, user2: user} do
        Accounts.add_org_user(org, user, %{role: @role})

        assert_error_sent(401, fn ->
          put(conn, Routes.api_org_user_path(conn, :update, org.name, user.id), role: "manage")
        end)
        |> assert_authorization_error()
      end
    end
  end

  defp create_org_user(%{user2: user, org: org}) do
    {:ok, org_user} = Accounts.add_org_user(org, user, %{role: :admin})
    {:ok, %{org_user: org_user}}
  end
end

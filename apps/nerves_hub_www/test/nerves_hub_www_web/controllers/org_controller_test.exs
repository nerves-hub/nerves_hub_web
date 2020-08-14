defmodule NervesHubWWWWeb.OrgControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: true

  alias NervesHubWebCore.Fixtures

  describe "new org" do
    test "renders form", %{conn: conn} do
      conn = get(conn, Routes.org_path(conn, :new))
      assert html_response(conn, 200) =~ "Create New Workspace"
    end
  end

  describe "create org" do
    test "redirects to edit when data is valid", %{conn: conn} do
      conn = post(conn, Routes.org_path(conn, :create), org: %{name: "An_Org"})
      assert redirected_to(conn) == Routes.product_path(conn, :index, "An_Org")
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, Routes.org_path(conn, :create), org: %{})
      assert html_response(conn, 200) =~ "Create New Workspace"
    end
  end

  describe "edit org" do
    test "renders form for editing org on conn", %{conn: conn, org: org} do
      conn = get(conn, Routes.org_path(conn, :edit, org.name))
      assert html_response(conn, 200)
    end

    test "does not render form for org not on conn", %{conn: conn} do
      user = Fixtures.user_fixture(%{name: "secret-user"})
      new_org = Fixtures.org_fixture(user, %{name: "Secret_Org_Name"})
      conn = get(conn, Routes.org_path(conn, :edit, new_org.name))
      assert html_response(conn, 404)
    end
  end

  describe "update org" do
    test "cannot update wrong org", %{conn: conn} do
      user = Fixtures.user_fixture(%{email: "new@org.com"})
      new_org = Fixtures.org_fixture(user, %{name: "Secret_Org_Name"})

      conn =
        put(conn, Routes.org_path(conn, :update, new_org.name), org: %{name: "Nefarious_Name"})

      assert html_response(conn, 404)

      new_conn =
        build_conn()
        |> Map.put(:assigns, %{org: new_org})
        |> init_test_session(%{"auth_user_id" => user.id})

      updated_conn = get(new_conn, Routes.org_path(conn, :edit, new_org.name))

      refute html_response(updated_conn, 200) =~ "Nefarious_Name"
    end

    test "redirects when data is valid", %{conn: conn, org: org} do
      conn = put(conn, Routes.org_path(conn, :update, org.name), org: %{name: "new_name"})

      assert redirected_to(conn) == Routes.org_path(conn, :edit, "new_name")
    end

    test "renders errors when data is invalid", %{conn: conn, org: org} do
      conn =
        put(
          conn,
          Routes.org_path(conn, :update, org.name),
          org: %{name: ""}
        )

      assert html_response(conn, 200) =~ "Workspace Settings"
      assert html_response(conn, 200) =~ "be blank"
    end
  end

  describe "send invite" do
    test "sends invite when user does not exist", %{conn: conn, org: org} do
      conn =
        post(conn, Routes.org_path(conn, :send_invite, org.name),
          invite: %{email: "nunya@bid.ness"}
        )

      assert redirected_to(conn) == Routes.org_path(conn, :edit, org.name)

      redirected_conn = get(conn, redirected_to(conn))

      assert html_response(redirected_conn, 200) =~ "User has been invited"
    end

    test "creates OrgUser when user already exists", %{conn: conn, org: org} do
      user = Fixtures.user_fixture(%{email: "who@der.com"})

      conn =
        post(conn, Routes.org_path(conn, :send_invite, org.name), invite: %{email: user.email})

      assert redirected_to(conn) == Routes.org_path(conn, :edit, org.name)

      redirected_conn = get(conn, redirected_to(conn))

      assert html_response(redirected_conn, 200) =~ "User has been added to #{org.name}"
    end

    test "errors when user exists and already member of org", %{
      conn: conn,
      org: org,
      user: user
    } do
      conn =
        post(conn, Routes.org_path(conn, :send_invite, org.name), invite: %{email: user.email})

      assert html_response(conn, 200) =~ user.email
      assert html_response(conn, 200) =~ "is already member"
    end
  end
end

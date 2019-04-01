defmodule NervesHubWWWWeb.OrgControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: true

  alias NervesHubWebCore.Fixtures

  describe "new org" do
    test "renders form", %{conn: conn} do
      conn = get(conn, org_path(conn, :new))
      assert html_response(conn, 200) =~ "New organization"
      refute html_response(conn, 200) =~ "href=\"" <> org_path(conn, :index) <> "\""
    end
  end

  describe "create org" do
    test "redirects to edit when data is valid", %{conn: conn, current_org: org} do
      conn = post(conn, org_path(conn, :create), org: %{name: "An Org"})

      assert %{id: id} = redirected_params(conn)
      assert redirected_to(conn) == org_path(conn, :edit, id)

      conn = get(conn, org_path(conn, :edit, id))
      assert html_response(conn, 200) =~ "Organization settings"
      assert html_response(conn, 200) =~ org.name
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, org_path(conn, :create), org: %{})
      assert html_response(conn, 200) =~ "New organization"
    end
  end

  describe "edit org" do
    test "renders form for editing org on conn", %{conn: conn, current_org: org} do
      conn = get(conn, org_path(conn, :edit, org))
      assert html_response(conn, 200) =~ "Organization settings"
    end

    test "does not render form for org not on conn", %{conn: conn} do
      user = Fixtures.user_fixture(%{name: "secret-user"})
      new_org = Fixtures.org_fixture(user, %{name: "Secret Org Name"})
      conn = get(conn, org_path(conn, :edit, new_org))
      refute html_response(conn, 200) =~ "Secret Org Name"
    end
  end

  describe "update org" do
    test "cannot update wrong org", %{conn: conn, current_org: org} do
      user = Fixtures.user_fixture(%{email: "new@org.com"})
      new_org = Fixtures.org_fixture(user, %{name: "Secret Org Name"})

      conn = put(conn, org_path(conn, :update, new_org), org: %{name: "Nefarious Name"})

      assert redirected_to(conn) == org_path(conn, :edit, org)

      new_conn =
        build_conn()
        |> Map.put(:assigns, %{org: new_org})
        |> init_test_session(%{"auth_user_id" => user.id, "current_org_id" => new_org.id})

      updated_conn = get(new_conn, org_path(conn, :edit, new_org))

      refute html_response(updated_conn, 200) =~ "Nefarious Name"
    end

    test "redirects when data is valid", %{conn: conn, current_org: org} do
      conn = put(conn, org_path(conn, :update, org), org: %{name: "new name"})

      assert redirected_to(conn) == org_path(conn, :edit, org)
    end

    test "renders errors when data is invalid", %{conn: conn, current_org: org} do
      conn =
        put(
          conn,
          org_path(conn, :update, org),
          org: %{name: ""}
        )

      assert html_response(conn, 200) =~ "Organization settings"
      assert html_response(conn, 200) =~ "be blank"
    end
  end

  describe "send invite" do
    test "sends invite when user does not exist", %{conn: conn, current_org: org} do
      conn = post(conn, org_path(conn, :send_invite), invite: %{email: "nunya@bid.ness"})

      assert redirected_to(conn) == org_path(conn, :edit, org.id)

      redirected_conn = get(conn, redirected_to(conn))

      assert html_response(redirected_conn, 200) =~ "User has been invited"
    end

    test "creates OrgUser when user already exists", %{conn: conn, current_org: org} do
      user = Fixtures.user_fixture(%{email: "who@der.com"})
      conn = post(conn, org_path(conn, :send_invite), invite: %{email: user.email})

      assert redirected_to(conn) == org_path(conn, :edit, org.id)

      redirected_conn = get(conn, redirected_to(conn))

      assert html_response(redirected_conn, 200) =~ "User has been added to #{org.name}"
    end

    test "errors when user exists and already member of org", %{conn: conn, current_user: user} do
      conn = post(conn, org_path(conn, :send_invite), invite: %{email: user.email})

      assert html_response(conn, 200) =~ user.email
      assert html_response(conn, 200) =~ "is already member"
    end
  end
end

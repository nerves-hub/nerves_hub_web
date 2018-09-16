defmodule NervesHubWWWWeb.OrgControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: true

  alias NervesHubCore.Fixtures

  describe "new org" do
    test "renders form", %{conn: conn} do
      conn = get(conn, org_path(conn, :new))
      assert html_response(conn, 200) =~ "New Org"
      refute html_response(conn, 200) =~ "href=\"" <> org_path(conn, :index) <> "\""
    end
  end

  describe "create org" do
    test "redirects to edit when data is valid", %{conn: conn, current_org: org} do
      conn = post(conn, org_path(conn, :create), org: %{name: "An Org"})

      assert %{id: id} = redirected_params(conn)
      assert redirected_to(conn) == org_path(conn, :edit, id)

      conn = get(conn, org_path(conn, :edit, id))
      assert html_response(conn, 200) =~ "Org Settings"
      assert html_response(conn, 200) =~ org.name
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, org_path(conn, :create), org: %{})
      assert html_response(conn, 200) =~ "New Org"
    end
  end

  describe "edit org" do
    test "renders form for editing org on conn", %{conn: conn, current_org: org} do
      conn = get(conn, org_path(conn, :edit, org))
      assert html_response(conn, 200) =~ "Org Settings"
    end

    test "does not render form for org not on conn", %{conn: conn, current_org: _org} do
      new_org = Fixtures.org_fixture(%{name: "Secret Org Name"})
      conn = get(conn, org_path(conn, :edit, new_org))
      refute html_response(conn, 200) =~ "Secret Org Name"
    end
  end

  describe "update org" do
    test "cannot update wrong org", %{conn: conn, current_org: org} do
      new_org = Fixtures.org_fixture(%{name: "Secret Org Name"})
      user = Fixtures.user_fixture(new_org, %{email: "new@org.com"})

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

      assert html_response(conn, 200) =~ "Org Settings"
      assert html_response(conn, 200) =~ "be blank"
    end
  end
end

defmodule NervesHubWWWWeb.OrgKeyControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: true

  alias NervesHubWebCore.Fixtures

  @update_attrs %{name: "new org's key", key: "bar"}
  @invalid_attrs %{name: nil}

  describe "index" do
    test "lists all org_keys", %{conn: conn} do
      conn = get(conn, org_key_path(conn, :index))
      assert html_response(conn, 200) =~ "Listing organization keys"
    end
  end

  describe "new org_keys" do
    test "renders form", %{conn: conn} do
      conn = get(conn, org_key_path(conn, :new))
      assert html_response(conn, 200) =~ "New organization keys"
    end
  end

  describe "create org_keys" do
    test "redirects to show when data is valid", %{conn: conn, current_org: org} do
      params = %{name: "foobarbazbangpow", key: "a key"}
      conn = post(conn, org_key_path(conn, :create), org_key: params)

      assert redirected_to(conn) == org_path(conn, :edit, org)

      conn = get(conn, org_path(conn, :edit, org))
      assert html_response(conn, 200) =~ params.name
    end

    test "renders errors when data is invalid", %{conn: conn, current_org: org} do
      conn = post(conn, org_key_path(conn, :create), org_key: @invalid_attrs)
      assert redirected_to(conn) == org_path(conn, :edit, org)
    end
  end

  describe "edit org_keys" do
    test "renders form for editing chosen org_keys", %{conn: conn, current_org: org} do
      org_key = Fixtures.org_key_fixture(org)
      conn = get(conn, org_key_path(conn, :edit, org_key))
      assert html_response(conn, 200) =~ "Edit organization key"
    end
  end

  describe "update org_key" do
    test "redirects when data is valid", %{conn: conn, current_org: org} do
      org_key = Fixtures.org_key_fixture(org)
      conn = put(conn, org_key_path(conn, :update, org_key), org_key: @update_attrs)

      assert redirected_to(conn) == org_path(conn, :edit, org)

      conn = get(conn, org_key_path(conn, :show, org_key))
      assert html_response(conn, 200)
    end

    test "renders errors when data is invalid", %{conn: conn, current_org: org} do
      org_key = Fixtures.org_key_fixture(org)

      conn =
        put(
          conn,
          org_key_path(conn, :update, org_key),
          org_key: @invalid_attrs
        )

      assert html_response(conn, 200) =~ "Edit organization key"
    end
  end

  describe "delete org_key" do
    test "deletes chosen org_key", %{conn: conn, current_org: org} do
      org_key = Fixtures.org_key_fixture(org)

      conn = delete(conn, org_key_path(conn, :delete, org_key))
      assert redirected_to(conn) == org_path(conn, :edit, org)

      assert_error_sent(404, fn ->
        get(conn, org_key_path(conn, :show, org_key))
      end)
    end

    test "returns error when key cannot be deleted", %{
      conn: conn,
      current_user: user,
      current_org: org
    } do
      org_key = Fixtures.org_key_fixture(org)

      product = Fixtures.product_fixture(user, org)
      Fixtures.firmware_fixture(org_key, product)

      conn = delete(conn, org_key_path(conn, :delete, org_key))
      assert html_response(conn, 200) =~ "Key is in use."
    end
  end
end

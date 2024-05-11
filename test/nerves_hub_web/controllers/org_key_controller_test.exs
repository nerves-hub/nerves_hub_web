defmodule NervesHubWeb.OrgKeyControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Fixtures

  @update_attrs %{name: "new org's key", key: "bar"}
  @invalid_attrs %{name: nil}

  describe "index" do
    test "lists all org_keys", %{conn: conn, org: org} do
      conn = get(conn, Routes.org_key_path(conn, :index, org.name))
      assert html_response(conn, 200) =~ "Signing Keys"
    end
  end

  describe "new org_keys" do
    test "renders form", %{conn: conn, org: org} do
      conn = get(conn, Routes.org_key_path(conn, :new, org.name))
      assert html_response(conn, 200) =~ "New Signing Key"
    end
  end

  describe "create org_keys" do
    test "redirects to index when data is valid", %{conn: conn, org: org} do
      params = %{name: "foobarbazbangpow", key: "a key"}
      conn = post(conn, Routes.org_key_path(conn, :create, org.name), org_key: params)

      assert redirected_to(conn) == Routes.org_key_path(conn, :index, org.name)

      conn = get(conn, Routes.org_key_path(conn, :index, org.name))
      assert html_response(conn, 200) =~ params.name
    end

    test "renders errors when data is invalid", %{conn: conn, org: org} do
      conn = post(conn, Routes.org_key_path(conn, :create, org.name), org_key: @invalid_attrs)
      assert redirected_to(conn) == Routes.org_key_path(conn, :index, org.name)
    end
  end

  describe "edit org_keys" do
    test "renders form for editing chosen org_keys", %{conn: conn, org: org} do
      org_key = Fixtures.org_key_fixture(org)
      conn = get(conn, Routes.org_key_path(conn, :edit, org.name, org_key))
      assert html_response(conn, 200) =~ "Edit Signing Key"
    end
  end

  describe "update org_key" do
    test "redirects when data is valid", %{conn: conn, org: org} do
      org_key = Fixtures.org_key_fixture(org)

      conn =
        put(conn, Routes.org_key_path(conn, :update, org.name, org_key), org_key: @update_attrs)

      assert redirected_to(conn) == Routes.org_key_path(conn, :index, org.name)

      conn = get(conn, Routes.org_key_path(conn, :show, org.name, org_key))
      assert html_response(conn, 200)
    end

    test "renders errors when data is invalid", %{conn: conn, org: org} do
      org_key = Fixtures.org_key_fixture(org)

      conn =
        put(
          conn,
          Routes.org_key_path(conn, :update, org.name, org_key),
          org_key: @invalid_attrs
        )

      assert html_response(conn, 200) =~ "Edit Signing Key"
    end
  end

  describe "delete org_key" do
    test "deletes chosen org_key", %{conn: conn, org: org} do
      org_key = Fixtures.org_key_fixture(org)

      conn = delete(conn, Routes.org_key_path(conn, :delete, org.name, org_key))
      assert redirected_to(conn) == Routes.org_key_path(conn, :index, org.name)

      assert_error_sent(404, fn ->
        get(conn, Routes.org_key_path(conn, :show, org.name, org_key))
      end)
    end

    test "returns error when key cannot be deleted", %{
      conn: conn,
      user: user,
      org: org
    } do
      org_key = Fixtures.org_key_fixture(org)

      product = Fixtures.product_fixture(user, org)
      Fixtures.firmware_fixture(org_key, product)

      conn = delete(conn, Routes.org_key_path(conn, :delete, org.name, org_key))
      assert html_response(conn, 200) =~ "Key is in use."
    end
  end
end

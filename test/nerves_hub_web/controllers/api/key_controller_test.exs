defmodule NervesHubWeb.API.KeyControllerTest do
  use NervesHubWeb.APIConnCase, async: true

  alias NervesHub.Fixtures
  alias NervesHub.Support.Fwup
  alias NervesHub.Accounts

  describe "index" do
    test "lists all keys", %{conn: conn, org: org} do
      conn = get(conn, Routes.api_key_path(conn, :index, org.name))
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "index roles" do
    test "error: missing org read", %{conn2: conn, org: org} do
      assert_raise(Ecto.NoResultsError, fn ->
        get(conn, Routes.api_key_path(conn, :index, org.name))
      end)
    end
  end

  describe "create keys" do
    @tags :tmp_dir
    test "renders key when data is valid", %{conn: conn, org: org, tmp_dir: tmp_dir} do
      name = "test"
      Fwup.gen_key_pair(name, tmp_dir)
      pub_key = Fwup.get_public_key(name)
      key = %{name: name, key: pub_key, org_id: org.id}

      conn = post(conn, Routes.api_key_path(conn, :create, org.name), key)
      assert json_response(conn, 201)["data"]

      conn = get(conn, Routes.api_key_path(conn, :show, org.name, key.name))
      assert json_response(conn, 200)["data"]["name"] == name
    end

    test "renders errors when data is invalid", %{conn: conn, org: org} do
      conn = post(conn, Routes.api_key_path(conn, :create, org.name))
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "create keys roles" do
    @tags :tmp_dir
    test "ok: org manage", %{conn2: conn, org: org, user2: user, tmp_dir: tmp_dir} do
      Accounts.add_org_user(org, user, %{role: :manage})

      name = "test"
      Fwup.gen_key_pair(name, tmp_dir)
      pub_key = Fwup.get_public_key(name)
      key = %{name: name, key: pub_key, org_id: org.id}

      conn = post(conn, Routes.api_key_path(conn, :create, org.name), key)
      assert json_response(conn, 201)["data"]

      conn = get(conn, Routes.api_key_path(conn, :show, org.name, key.name))
      assert json_response(conn, 200)["data"]["name"] == name
    end

    test "error: org view", %{conn2: conn, org: org, user2: user} do
      Accounts.add_org_user(org, user, %{role: :view})
      name = "test"
      Fwup.gen_key_pair(name)
      pub_key = Fwup.get_public_key(name)
      key = %{name: name, key: pub_key, org_id: org.id}

      conn = post(conn, Routes.api_key_path(conn, :create, org.name), key)
      assert json_response(conn, 403)["status"] != ""
    end
  end

  describe "delete key" do
    setup [:create_key]

    test "deletes chosen key", %{conn: conn, org: org, key: key} do
      conn = delete(conn, Routes.api_key_path(conn, :delete, org.name, key.name))
      assert response(conn, 204)

      conn = get(conn, Routes.api_key_path(conn, :show, org.name, key.name))

      assert response(conn, 404)
    end
  end

  describe "delete key roles" do
    setup [:create_key]

    test "ok: org manage", %{user2: user, conn2: conn, org: org, key: key} do
      Accounts.add_org_user(org, user, %{role: :manage})
      conn = delete(conn, Routes.api_key_path(conn, :delete, org.name, key.name))
      assert response(conn, 204)
    end

    test "error: org view", %{user2: user, conn2: conn, org: org, key: key} do
      Accounts.add_org_user(org, user, %{role: :view})
      conn = delete(conn, Routes.api_key_path(conn, :delete, org.name, key.name))
      assert json_response(conn, 403)["status"] != ""
    end
  end

  defp create_key(%{user: user, org: org}) do
    key = Fixtures.org_key_fixture(org, user)
    {:ok, %{key: key}}
  end
end

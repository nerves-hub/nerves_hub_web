defmodule NervesHubAPIWeb.KeyControllerTest do
  use NervesHubAPIWeb.ConnCase, async: true

  alias NervesHubWebCore.Fixtures
  alias NervesHubWebCore.Support.Fwup
  alias NervesHubWebCore.Accounts

  describe "index" do
    test "lists all keys", %{conn: conn, org: org} do
      conn = get(conn, Routes.key_path(conn, :index, org.name))
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "index roles" do
    test "error: missing org read", %{conn2: conn, org: org} do
      conn = get(conn, Routes.key_path(conn, :index, org.name))
      assert json_response(conn, 403)["status"] != ""
    end
  end

  describe "create keys" do
    test "renders key when data is valid", %{conn: conn, org: org} do
      name = "test"
      Fwup.gen_key_pair(name)
      pub_key = Fwup.get_public_key(name)
      key = %{name: name, key: pub_key, org_id: org.id}

      conn = post(conn, Routes.key_path(conn, :create, org.name), key)
      assert json_response(conn, 201)["data"]

      conn = get(conn, Routes.key_path(conn, :show, org.name, key.name))
      assert json_response(conn, 200)["data"]["name"] == name
    end

    test "renders errors when data is invalid", %{conn: conn, org: org} do
      conn = post(conn, Routes.key_path(conn, :create, org.name))
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "create keys roles" do
    test "ok: org write", %{conn2: conn, org: org, user2: user} do
      Accounts.add_org_user(org, user, %{role: :write})

      name = "test"
      Fwup.gen_key_pair(name)
      pub_key = Fwup.get_public_key(name)
      key = %{name: name, key: pub_key, org_id: org.id}

      conn = post(conn, Routes.key_path(conn, :create, org.name), key)
      assert json_response(conn, 201)["data"]

      conn = get(conn, Routes.key_path(conn, :show, org.name, key.name))
      assert json_response(conn, 200)["data"]["name"] == name
    end

    test "error: org read", %{conn2: conn, org: org, user2: user} do
      Accounts.add_org_user(org, user, %{role: :read})
      name = "test"
      Fwup.gen_key_pair(name)
      pub_key = Fwup.get_public_key(name)
      key = %{name: name, key: pub_key, org_id: org.id}

      conn = post(conn, Routes.key_path(conn, :create, org.name), key)
      assert json_response(conn, 403)["status"] != ""
    end
  end

  describe "delete key" do
    setup [:create_key]

    test "deletes chosen key", %{conn: conn, org: org, key: key} do
      conn = delete(conn, Routes.key_path(conn, :delete, org.name, key.name))
      assert response(conn, 204)

      conn = get(conn, Routes.key_path(conn, :show, org.name, key.name))

      assert response(conn, 404)
    end
  end

  describe "delete key roles" do
    setup [:create_key]

    test "ok: org delete", %{user2: user, conn2: conn, org: org, key: key} do
      Accounts.add_org_user(org, user, %{role: :delete})
      conn = delete(conn, Routes.key_path(conn, :delete, org.name, key.name))
      assert response(conn, 204)
    end

    test "error: org write", %{user2: user, conn2: conn, org: org, key: key} do
      Accounts.add_org_user(org, user, %{role: :write})
      conn = delete(conn, Routes.key_path(conn, :delete, org.name, key.name))
      assert json_response(conn, 403)["status"] != ""
    end

    test "error: org read", %{user2: user, conn2: conn, org: org, key: key} do
      Accounts.add_org_user(org, user, %{role: :read})
      conn = delete(conn, Routes.key_path(conn, :delete, org.name, key.name))
      assert json_response(conn, 403)["status"] != ""
    end
  end

  defp create_key(%{org: org}) do
    key = Fixtures.org_key_fixture(org)
    {:ok, %{key: key}}
  end
end

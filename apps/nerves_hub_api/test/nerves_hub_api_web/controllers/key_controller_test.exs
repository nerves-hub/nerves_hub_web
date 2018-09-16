defmodule NervesHubAPIWeb.KeyControllerTest do
  use NervesHubAPIWeb.ConnCase, async: true

  alias NervesHubCore.Fixtures

  @test_firmware_path Path.expand("../../../../../test/fixtures/firmware", __DIR__)
  @fw_key_path Path.join(@test_firmware_path, "fwup-key1.pub")

  describe "index" do
    test "lists all keys", %{conn: conn, org: org} do
      conn = get(conn, key_path(conn, :index, org.name))
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "create keys" do
    test "renders key when data is valid", %{conn: conn, org: org} do
      name = "test"
      key = %{name: name, key: File.read!(@fw_key_path), org_id: org.id}

      conn = post(conn, key_path(conn, :create, org.name), key)
      assert json_response(conn, 201)["data"]

      conn = get(conn, key_path(conn, :show, org.name, key.name))
      assert json_response(conn, 200)["data"]["name"] == name
    end

    test "renders errors when data is invalid", %{conn: conn, org: org} do
      conn = post(conn, key_path(conn, :create, org.name))
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "delete key" do
    setup [:create_key]

    test "deletes chosen key", %{conn: conn, org: org, key: key} do
      conn = delete(conn, key_path(conn, :delete, org.name, key.name))
      assert response(conn, 204)

      conn = get(conn, key_path(conn, :show, org.name, key.name))

      assert response(conn, 404)
    end
  end

  defp create_key(%{org: org}) do
    key = Fixtures.org_key_fixture(org, %{name: "api"})
    {:ok, %{key: key}}
  end
end

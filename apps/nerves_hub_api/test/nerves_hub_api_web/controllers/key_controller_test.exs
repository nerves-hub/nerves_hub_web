defmodule NervesHubAPIWeb.KeyControllerTest do
  use NervesHubAPIWeb.ConnCase

  alias NervesHubCore.Fixtures

  @test_firmware_path Path.expand("../../../../../test/fixtures/firmware", __DIR__)
  @fw_key_path Path.join(@test_firmware_path, "fwup-key1.pub")

  describe "index" do
    test "lists all keys", %{conn: conn} do
      conn = get(conn, key_path(conn, :index))
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "create keys" do
    test "renders key when data is valid", %{org: org, conn: conn} do
      name = "test"
      key = %{name: name, key: File.read!(@fw_key_path), org_id: org.id}

      conn = post(conn, key_path(conn, :create), key)
      assert json_response(conn, 201)["data"]

      conn = get(conn, key_path(conn, :show, key.name))
      assert json_response(conn, 200)["data"]["name"] == name
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, key_path(conn, :create))
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "delete key" do
    setup [:create_key]

    test "deletes chosen key", %{conn: conn, key: key} do
      conn = delete(conn, key_path(conn, :delete, key.name))
      assert response(conn, 204)

      conn = get(conn, key_path(conn, :show, key.name))

      assert response(conn, 404)
    end
  end

  defp create_key(%{org: org}) do
    key = Fixtures.org_key_fixture(org, %{name: "api"})
    {:ok, %{key: key}}
  end
end

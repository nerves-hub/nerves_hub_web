defmodule NervesHubWeb.API.V2.ScriptTest do
  use NervesHubWeb.AshAPIConnCase, async: false

  alias NervesHub.Repo
  alias NervesHub.Scripts.Script

  setup %{user: user, product: product} do
    {:ok, script} =
      %Script{}
      |> Ecto.Changeset.change(%{
        name: "test-script",
        text: "echo hello",
        product_id: product.id,
        created_by_id: user.id,
        last_updated_by_id: user.id
      })
      |> Repo.insert()

    [script: script]
  end

  describe "index" do
    test "lists scripts", %{conn: conn, script: script} do
      conn = get(conn, "/api/v2/scripts")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      names = Enum.map(resp["data"], & &1["attributes"]["name"])
      assert script.name in names
    end
  end

  describe "show" do
    test "returns a script by id", %{conn: conn, script: script} do
      conn = get(conn, "/api/v2/scripts/#{script.id}")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["name"] == script.name
    end
  end

  describe "list_by_product" do
    test "lists scripts by product", %{conn: conn, product: product, script: script} do
      conn = get(conn, "/api/v2/scripts/by-product/#{product.id}")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      names = Enum.map(resp["data"], & &1["attributes"]["name"])
      assert script.name in names
    end
  end

  describe "get_by_product_and_name" do
    test "returns a script by product and name", %{conn: conn, product: product, script: script} do
      conn = get(conn, "/api/v2/scripts/by-product/#{product.id}/by-name/#{script.name}")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["name"] == script.name
    end
  end

  describe "create" do
    test "creates a script", %{conn: conn, product: product, user: user} do
      conn =
        post(conn, "/api/v2/scripts", %{
          "data" => %{
            "type" => "script",
            "attributes" => %{
              "name" => "new-script",
              "text" => "echo world",
              "product_id" => product.id,
              "created_by_id" => user.id,
              "last_updated_by_id" => user.id
            }
          }
        })

      resp = json_response(conn, 201)
      assert resp["data"]["attributes"]["name"] == "new-script"
    end
  end

  describe "update" do
    test "updates a script", %{conn: conn, script: script} do
      conn =
        patch(conn, "/api/v2/scripts/#{script.id}", %{
          "data" => %{
            "type" => "script",
            "id" => "#{script.id}",
            "attributes" => %{
              "name" => "updated-script"
            }
          }
        })

      resp = json_response(conn, 200)
      assert resp["data"]["attributes"]["name"] == "updated-script"
    end
  end

  describe "delete" do
    test "deletes a script", %{conn: conn, script: script} do
      conn = delete(conn, "/api/v2/scripts/#{script.id}")
      assert response(conn, 200)
    end
  end
end

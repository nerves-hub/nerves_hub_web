defmodule NervesHubWeb.API.V2.JITPTest do
  use NervesHubWeb.AshAPIConnCase, async: false

  alias NervesHub.Repo
  alias NervesHub.Devices.CACertificate.JITP

  setup %{product: product} do
    jitp =
      Repo.insert!(%JITP{
        product_id: product.id,
        tags: ["test", "jitp"],
        description: "Test JITP"
      })

    [jitp: jitp]
  end

  describe "index" do
    test "lists JITP records", %{conn: conn} do
      conn = get(conn, "/api/v2/jitp")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      assert length(resp["data"]) >= 1
    end
  end

  describe "show" do
    test "returns a JITP by id", %{conn: conn, jitp: jitp} do
      conn = get(conn, "/api/v2/jitp/#{jitp.id}")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["description"] == "Test JITP"
      assert resp["data"]["attributes"]["tags"] == ["test", "jitp"]
    end
  end

  describe "create" do
    test "creates a JITP record", %{conn: conn, product: product} do
      conn =
        post(conn, "/api/v2/jitp", %{
          "data" => %{
            "type" => "jitp",
            "attributes" => %{
              "product_id" => product.id,
              "tags" => ["new", "device"],
              "description" => "New JITP config"
            }
          }
        })

      resp = json_response(conn, 201)
      assert resp["data"]["attributes"]["description"] == "New JITP config"
    end
  end

  describe "update" do
    test "updates a JITP record", %{conn: conn, jitp: jitp} do
      conn =
        patch(conn, "/api/v2/jitp/#{jitp.id}", %{
          "data" => %{
            "type" => "jitp",
            "id" => "#{jitp.id}",
            "attributes" => %{
              "description" => "Updated JITP"
            }
          }
        })

      resp = json_response(conn, 200)
      assert resp["data"]["attributes"]["description"] == "Updated JITP"
    end
  end

  describe "list_by_product" do
    test "lists JITP by product", %{conn: conn, product: product} do
      conn = get(conn, "/api/v2/jitp/by-product/#{product.id}")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      assert length(resp["data"]) >= 1
    end
  end

  describe "delete" do
    test "deletes a JITP record", %{conn: conn, jitp: jitp} do
      conn = delete(conn, "/api/v2/jitp/#{jitp.id}")
      assert response(conn, 200)
    end
  end
end

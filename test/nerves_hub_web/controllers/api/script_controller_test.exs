defmodule NervesHubWeb.API.ScriptControllerTest do
  use NervesHubWeb.APIConnCase, async: true

  alias NervesHub.Fixtures

  setup context do
    org_key = Fixtures.org_key_fixture(context.org, context.user)
    firmware = Fixtures.firmware_fixture(org_key, context.product)
    device = Fixtures.device_fixture(context.org, context.product, firmware)

    Map.put(context, :device, device)
  end

  describe "index" do
    test "lists scripts with device", %{conn: conn, product: product, device: device, user: user} do
      script = Fixtures.support_script_fixture(product, user)
      conn = get(conn, Routes.api_script_path(conn, :index, device))
      data = [script_response] = json_response(conn, 200)["data"]
      assert Enum.count(data) == 1
      assert script_response["id"] == script.id
    end

    test "lists scripts for product", %{conn: conn, org: org, product: product, user: user} do
      script = Fixtures.support_script_fixture(product, user)
      conn = get(conn, Routes.api_script_path(conn, :index, org.name, product.name))
      data = [script_response] = json_response(conn, 200)["data"]
      assert Enum.count(data) == 1
      assert script_response["id"] == script.id
    end

    test "list scripts with tag", %{conn: conn, product: product, device: device, user: user} do
      _script = Fixtures.support_script_fixture(product, user)
      script_with_tags = Fixtures.support_script_fixture(product, user, %{tags: "hello,world"})

      # Assert no filters returns both scripts
      conn = get(conn, Routes.api_script_path(conn, :index, device))
      data = json_response(conn, 200)["data"]
      assert Enum.count(data) == 2

      # Assert filtering on tag returns tagged script
      conn = get(conn, Routes.api_script_path(conn, :index, device), %{filters: %{tags: "hello"}})
      data = [script_response] = json_response(conn, 200)["data"]
      assert Enum.count(data) == 1
      assert script_response["id"] == script_with_tags.id
    end

    test "returns pagination metadata", %{conn: conn, product: product, device: device, user: user} do
      _script = Fixtures.support_script_fixture(product, user)

      conn = get(conn, Routes.api_script_path(conn, :index, device))
      response = json_response(conn, 200)

      assert Map.has_key?(response, "data")
      assert Map.has_key?(response, "pagination")

      pagination = response["pagination"]
      assert pagination["page_number"] == 1
      assert pagination["page_size"] == 25
      assert pagination["total_entries"] == 1
      assert pagination["total_pages"] == 1
    end

    test "respects pagination parameters with device scope", %{conn: conn, product: product, device: device, user: user} do
      # Create 5 scripts
      _scripts = for i <- 1..5, do: Fixtures.support_script_fixture(product, user, %{name: "script#{i}"})

      # Get first page with page_size=2
      conn =
        get(conn, Routes.api_script_path(conn, :index, device), %{
          pagination: %{page: 1, page_size: 2}
        })

      response = json_response(conn, 200)

      assert length(response["data"]) == 2
      assert response["pagination"]["page_number"] == 1
      assert response["pagination"]["page_size"] == 2
      assert response["pagination"]["total_entries"] == 5
      assert response["pagination"]["total_pages"] == 3

      # Get second page with page_size=2
      conn =
        get(conn, Routes.api_script_path(conn, :index, device), %{
          pagination: %{page: 2, page_size: 2}
        })

      response = json_response(conn, 200)

      assert length(response["data"]) == 2
      assert response["pagination"]["page_number"] == 2
      assert response["pagination"]["page_size"] == 2
      assert response["pagination"]["total_entries"] == 5
      assert response["pagination"]["total_pages"] == 3

      # Get third page with page_size=2 (should have 1 item)
      conn =
        get(conn, Routes.api_script_path(conn, :index, device), %{
          pagination: %{page: 3, page_size: 2}
        })

      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert response["pagination"]["page_number"] == 3
      assert response["pagination"]["total_entries"] == 5
    end

    test "respects pagination parameters with product scope", %{conn: conn, org: org, product: product, user: user} do
      # Create 3 scripts
      _scripts = for i <- 1..3, do: Fixtures.support_script_fixture(product, user, %{name: "script#{i}"})

      # Get page with custom page_size
      conn =
        get(conn, Routes.api_script_path(conn, :index, org.name, product.name), %{
          pagination: %{page: 1, page_size: 2}
        })

      response = json_response(conn, 200)

      assert length(response["data"]) == 2
      assert response["pagination"]["page_number"] == 1
      assert response["pagination"]["page_size"] == 2
      assert response["pagination"]["total_entries"] == 3
      assert response["pagination"]["total_pages"] == 2
    end

    test "handles string pagination parameters", %{conn: conn, product: product, device: device, user: user} do
      # Create 3 scripts
      _scripts = for i <- 1..3, do: Fixtures.support_script_fixture(product, user, %{name: "script#{i}"})

      # Send pagination params as strings (as they come from URL query params)
      conn =
        get(conn, Routes.api_script_path(conn, :index, device), %{
          pagination: %{"page" => "2", "page_size" => "1"}
        })

      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert response["pagination"]["page_number"] == 2
      assert response["pagination"]["page_size"] == 1
      assert response["pagination"]["total_entries"] == 3
    end
  end
end

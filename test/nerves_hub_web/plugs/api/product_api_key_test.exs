defmodule NervesHubWeb.API.Plugs.ProductApiKeyTest do
  use ExUnit.Case, async: false
  use NervesHub.DataCase

  import Plug.Test
  import Plug.Conn

  alias NervesHub.Fixtures
  alias NervesHub.Products
  alias NervesHubWeb.API.Plugs.AuthenticateUserOrProduct

  setup do
    {:ok, Fixtures.standard_fixture()}
  end

  describe "product API key authentication" do
    test "authenticates with valid product API key using 'token' scheme", %{
      product: product,
      org: org
    } do
      {:ok, api_key} = Products.create_product_api_key(product, %{name: "Test API Key"})

      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "token #{api_key.key}")
        |> AuthenticateUserOrProduct.call([])

      assert conn.assigns.product.id == product.id
      assert conn.assigns.org.id == org.id
      assert conn.assigns.actor == conn.assigns.product
    end

    test "authenticates with valid product API key using 'Bearer' scheme", %{
      product: product,
      org: org
    } do
      {:ok, api_key} = Products.create_product_api_key(product, %{name: "Test API Key"})

      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Bearer #{api_key.key}")
        |> AuthenticateUserOrProduct.call([])

      assert conn.assigns.product.id == product.id
      assert conn.assigns.org.id == org.id
      assert conn.assigns.actor == conn.assigns.product
    end

    test "authenticates with valid product API key using mixed case 'BEARER' scheme", %{
      product: product,
      org: org
    } do
      {:ok, api_key} = Products.create_product_api_key(product, %{name: "Test API Key"})

      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "BEARER #{api_key.key}")
        |> AuthenticateUserOrProduct.call([])

      assert conn.assigns.product.id == product.id
      assert conn.assigns.org.id == org.id
    end

    test "raises UnauthorizedError with invalid product API key" do
      assert_raise NervesHubWeb.UnauthorizedError, fn ->
        conn(:get, "/")
        |> put_req_header("authorization", "token nhp_api_invalid_key_12345")
        |> AuthenticateUserOrProduct.call([])
      end
    end

    test "raises UnauthorizedError with deactivated product API key", %{product: product} do
      {:ok, api_key} = Products.create_product_api_key(product, %{name: "Test API Key"})
      {:ok, _deactivated} = Products.deactivate_product_api_key(product, api_key.id)

      assert_raise NervesHubWeb.UnauthorizedError, fn ->
        conn(:get, "/")
        |> put_req_header("authorization", "token #{api_key.key}")
        |> AuthenticateUserOrProduct.call([])
      end
    end

    test "raises UnauthorizedError when product API key format is valid but key doesn't exist" do
      # Valid format (starts with nhp_api_) but non-existent key
      assert_raise NervesHubWeb.UnauthorizedError, fn ->
        conn(:get, "/")
        |> put_req_header("authorization", "token nhp_api_nonexistent1234567890abcdef")
        |> AuthenticateUserOrProduct.call([])
      end
    end

    test "raises UnauthorizedError with missing authorization header" do
      assert_raise NervesHubWeb.UnauthorizedError, fn ->
        conn(:get, "/")
        |> AuthenticateUserOrProduct.call([])
      end
    end

    test "raises UnauthorizedError with malformed authorization header" do
      assert_raise NervesHubWeb.UnauthorizedError, fn ->
        conn(:get, "/")
        |> put_req_header("authorization", "invalid-format")
        |> AuthenticateUserOrProduct.call([])
      end
    end

    test "raises UnauthorizedError with only scheme in authorization header" do
      assert_raise NervesHubWeb.UnauthorizedError, fn ->
        conn(:get, "/")
        |> put_req_header("authorization", "token")
        |> AuthenticateUserOrProduct.call([])
      end
    end

    test "raises UnauthorizedError with empty authorization header" do
      assert_raise NervesHubWeb.UnauthorizedError, fn ->
        conn(:get, "/")
        |> put_req_header("authorization", "")
        |> AuthenticateUserOrProduct.call([])
      end
    end

    test "raises UnauthorizedError with unsupported scheme", %{product: product} do
      {:ok, api_key} = Products.create_product_api_key(product, %{name: "Test API Key"})

      assert_raise NervesHubWeb.UnauthorizedError, fn ->
        conn(:get, "/")
        |> put_req_header("authorization", "Basic #{api_key.key}")
        |> AuthenticateUserOrProduct.call([])
      end
    end

    test "product and org are preloaded with association", %{product: product, org: org} do
      {:ok, api_key} = Products.create_product_api_key(product, %{name: "Test API Key"})

      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "token #{api_key.key}")
        |> AuthenticateUserOrProduct.call([])

      # Verify that the org is properly loaded
      assert conn.assigns.product.org.id == org.id
      assert conn.assigns.product.org.name == org.name
    end

    test "handles product API key with extra parts in header", %{
      product: product,
      org: org
    } do
      {:ok, api_key} = Products.create_product_api_key(product, %{name: "Test API Key"})

      # The plug splits on space and takes scheme and token, ignoring extra parts
      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "token #{api_key.key} extra")
        |> AuthenticateUserOrProduct.call([])

      assert conn.assigns.product.id == product.id
      assert conn.assigns.org.id == org.id
    end
  end

  describe "product API key prefix detection" do
    test "correctly identifies product API key by nhp_api_ prefix", %{product: product} do
      {:ok, api_key} = Products.create_product_api_key(product, %{name: "Test API Key"})

      # Verify the key starts with the expected prefix
      assert String.starts_with?(api_key.key, "nhp_api_")

      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "token #{api_key.key}")
        |> AuthenticateUserOrProduct.call([])

      # Should assign product, not user
      assert Map.has_key?(conn.assigns, :product)
      assert Map.has_key?(conn.assigns, :org)
      assert conn.assigns.actor == conn.assigns.product
    end
  end
end

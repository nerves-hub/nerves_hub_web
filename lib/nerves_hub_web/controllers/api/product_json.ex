defmodule NervesHubWeb.API.ProductJSON do
  @moduledoc false

  def index(%{products: products}) do
    %{data: for(product <- products, do: product(product))}
  end

  def show(%{product: product}) do
    %{data: product(product)}
  end

  def product(product) do
    %{
      name: product.name,
      require_unique_firmware_version: product.require_unique_firmware_version,
      allowed_update_tools: product.allowed_update_tools,
      allow_unsigned_esp_idf_firmware: product.allow_unsigned_esp_idf_firmware
    }
  end
end

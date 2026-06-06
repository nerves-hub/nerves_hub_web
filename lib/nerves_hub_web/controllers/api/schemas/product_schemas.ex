defmodule NervesHubWeb.API.Schemas.ProductSchemas do
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule Product do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        name: %Schema{
          type: :string,
          pattern: ~r/[a-zA-Z][a-zA-Z0-9_]+/
        }
      },
      example: %{
        "name" => "Example Product"
      }
    })
  end

  defmodule ProductListResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for multiple products",
      type: :object,
      properties: %{
        data: %Schema{description: "The products details", type: :array, items: Product}
      },
      example: %{
        "data" => [
          %{
            "name" => "Example Product"
          },
          %{
            "name" => "Another Example Product"
          }
        ]
      }
    })
  end

  defmodule ProductCreationRequest do
    OpenApiSpex.schema(%{
      description: "POST body for creating a product",
      type: :object,
      properties: %{
        product: %Schema{
          properties: %{
            name: %Schema{type: :string}
          },
          required: [:name]
        }
      },
      required: [:product],
      example: %{
        "product" => %{
          "name" => "ExampleProduct"
        }
      }
    })
  end

  defmodule ProductUpdateRequest do
    OpenApiSpex.schema(%{
      description: "POST body for updating a product",
      type: :object,
      properties: %{
        product: %Schema{
          properties: %{}
        }
      }
    })
  end
end

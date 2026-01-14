defmodule NervesHubWeb.API.Schemas.ProductSchemas do
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule Product do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        name: %Schema{
          type: :string,
          pattern: ~r/[a-zA-Z][a-zA-Z0-9_]+/
        },
        inserted_at: %Schema{
          type: :string,
          description: "Creation timestamp",
          format: :"date-time"
        },
        updated_at: %Schema{
          type: :string,
          description: "Last updated timestamp",
          format: :"date-time"
        }
      },
      example: %{
        "id" => 123,
        "name" => "Example Product",
        "inserted_at" => "2017-09-12T12:34:55Z",
        "updated_at" => "2017-09-12T12:34:55Z"
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
            "id" => 123,
            "name" => "Example Product",
            "inserted_at" => "2017-09-12T12:34:55Z",
            "updated_at" => "2017-09-13T10:11:12Z"
          },
          %{
            "id" => 246,
            "name" => "Another Example Product",
            "inserted_at" => "2019-09-12T12:34:55Z",
            "updated_at" => "2019-09-13T10:11:12Z"
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

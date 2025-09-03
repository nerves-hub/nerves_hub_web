defmodule NervesHubWeb.API.Schemas.ProductSchemas do
  alias OpenApiSpex.Schema
  require OpenApiSpex

  defmodule Product do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      example: %{
        "id" => 123,
        "inserted_at" => "2017-09-12T12:34:55Z",
        "name" => "Example Product",
        "updated_at" => "2017-09-12T12:34:55Z"
      },
      properties: %{
        id: %Schema{type: :integer},
        inserted_at: %Schema{
          description: "Creation timestamp",
          format: :"date-time",
          type: :string
        },
        name: %Schema{
          pattern: ~r/[a-zA-Z][a-zA-Z0-9_]+/,
          type: :string
        },
        updated_at: %Schema{
          description: "Last updated timestamp",
          format: :"date-time",
          type: :string
        }
      },
      type: :object
    })
  end

  defmodule ProductListResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for multiple products",
      example: %{
        "data" => [
          %{
            "id" => 123,
            "inserted_at" => "2017-09-12T12:34:55Z",
            "name" => "Example Product",
            "updated_at" => "2017-09-13T10:11:12Z"
          },
          %{
            "id" => 246,
            "inserted_at" => "2019-09-12T12:34:55Z",
            "name" => "Another Example Product",
            "updated_at" => "2019-09-13T10:11:12Z"
          }
        ]
      },
      properties: %{
        data: %Schema{description: "The products details", items: Product, type: :array}
      },
      type: :object
    })
  end

  defmodule ProductCreationRequest do
    OpenApiSpex.schema(%{
      description: "POST body for creating a product",
      example: %{
        "product" => %{
          "name" => "ExampleProduct"
        }
      },
      properties: %{
        product: %Schema{
          properties: %{
            name: %Schema{type: :string}
          },
          required: [:name]
        }
      },
      required: [:product],
      type: :object
    })
  end

  defmodule ProductUpdateRequest do
    OpenApiSpex.schema(%{
      description: "POST body for updating a product",
      properties: %{
        product: %Schema{
          properties: %{}
        }
      },
      type: :object
    })
  end
end

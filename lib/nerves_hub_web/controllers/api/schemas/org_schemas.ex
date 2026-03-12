defmodule NervesHubWeb.API.Schemas.OrgSchemas do
  alias NervesHubWeb.API.Schemas.ProductSchemas
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule Org do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        name: %Schema{type: :string},
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"},
        products: %Schema{
          type: :array,
          items: ProductSchemas.Product,
          description: "Included when requested via ?include=products",
          nullable: true
        }
      },
      example: %{
        "data" => %{
          "name" => "example_org",
          "inserted_at" => "2024-01-01T00:00:00Z",
          "updated_at" => "2024-01-01T00:00:00Z",
          "products" => [%{"name" => "MyProduct"}]
        }
      }
    })
  end

  defmodule OrgListResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for multiple Organizations",
      type: :object,
      properties: %{
        data: %Schema{description: "The Organizations", type: :array, items: Org}
      },
      example: %{
        "data" => [
          %{
            "name" => "example_org",
            "inserted_at" => "2024-01-01T00:00:00Z",
            "updated_at" => "2024-01-01T00:00:00Z"
          }
        ]
      }
    })
  end
end

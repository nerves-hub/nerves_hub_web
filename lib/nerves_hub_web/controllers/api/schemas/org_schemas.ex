defmodule NervesHubWeb.API.Schemas.OrgSchemas do
  alias NervesHubWeb.API.OpenAPI.SchemaHelpers
  alias NervesHubWeb.API.Schemas.ProductSchemas
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule Org do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        name: %Schema{type: :string},
        inserted_at: SchemaHelpers.naive_timestamp("When it was created"),
        updated_at: SchemaHelpers.naive_timestamp("When it was last changed"),
        products: %Schema{
          type: :array,
          items: ProductSchemas.Product,
          description: "Included when requested via ?include=products",
          nullable: true
        }
      },
      example: %{
        "name" => "example_org",
        "inserted_at" => "2024-01-01T00:00:00",
        "updated_at" => "2024-01-01T00:00:00",
        "products" => [%{"name" => "MyProduct"}]
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
            "inserted_at" => "2024-01-01T00:00:00",
            "updated_at" => "2024-01-01T00:00:00"
          }
        ]
      }
    })
  end
end

defmodule NervesHubWeb.API.Schemas.ErrorSchemas do
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule ErrorResponse do
    OpenApiSpex.schema(%{
      description: "Error response",
      type: :object,
      properties: %{
        errors: %Schema{
          type: :object,
          properties: %{
            detail: %Schema{type: :string}
          }
        }
      },
      example: %{
        "errors" => %{"detail" => "Resource Not Found or Authorization Insufficient"}
      }
    })
  end

  defmodule ChangesetErrorResponse do
    OpenApiSpex.schema(%{
      description: "Validation error response",
      type: :object,
      properties: %{
        errors: %Schema{
          type: :object,
          additionalProperties: %Schema{
            type: :array,
            items: %Schema{type: :string}
          }
        }
      },
      example: %{
        "errors" => %{"identifier" => ["can't be blank"]}
      }
    })
  end
end

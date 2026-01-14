defmodule NervesHubWeb.API.Schemas.OrgUserSchemas do
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule OrgUser do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        name: %Schema{type: :string},
        email: %Schema{type: :string},
        role: %Schema{type: :string, enum: ["admin", "manage", "view"]}
      },
      example: %{
        "data" => %{
          "name" => "Jane Person",
          "email" => "jane@person.com",
          "role" => "admin"
        }
      }
    })
  end

  defmodule OrgUserListResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for multiple Organization Users",
      type: :object,
      properties: %{
        data: %Schema{description: "The Organization Users details", type: :array, items: OrgUser}
      },
      example: %{
        "data" => [
          %{
            "name" => "Jane Person",
            "email" => "jane@person.com",
            "role" => "admin"
          },
          %{
            "name" => "Jane Person",
            "email" => "jane@person.com",
            "role" => "view"
          }
        ]
      }
    })
  end

  defmodule OrgUserCreationRequest do
    OpenApiSpex.schema(%{
      description: "POST body for adding or inviting a user to an organization",
      type: :object,
      properties: %{
        email: %Schema{type: :string},
        role: %Schema{type: :string, enum: ["admin", "manage", "view"]}
      },
      required: [:email, :role],
      example: %{
        "email" => "jane@person.com",
        "role" => "manage"
      }
    })
  end

  defmodule OrgUserUpdateRequest do
    OpenApiSpex.schema(%{
      description: "POST body for updating a users organization membership",
      type: :object,
      properties: %{
        role: %Schema{type: :string, enum: ["admin", "manage", "view"]}
      },
      required: [:role],
      example: %{
        "role" => "manage"
      }
    })
  end
end

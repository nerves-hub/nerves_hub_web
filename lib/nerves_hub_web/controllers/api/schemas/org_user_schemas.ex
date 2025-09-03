defmodule NervesHubWeb.API.Schemas.OrgUserSchemas do
  alias OpenApiSpex.Schema
  require OpenApiSpex

  defmodule OrgUser do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      example: %{
        "data" => %{
          "email" => "jane@person.com",
          "name" => "Jane Person",
          "role" => "admin"
        }
      },
      properties: %{
        email: %Schema{type: :string},
        name: %Schema{type: :string},
        role: %Schema{enum: ["admin", "manage", "view"], type: :string}
      },
      type: :object
    })
  end

  defmodule OrgUserListResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for multiple Organization Users",
      example: %{
        "data" => [
          %{
            "email" => "jane@person.com",
            "name" => "Jane Person",
            "role" => "admin"
          },
          %{
            "email" => "jane@person.com",
            "name" => "Jane Person",
            "role" => "view"
          }
        ]
      },
      properties: %{
        data: %Schema{description: "The Organization Users details", items: OrgUser, type: :array}
      },
      type: :object
    })
  end

  defmodule OrgUserCreationRequest do
    OpenApiSpex.schema(%{
      description: "POST body for adding or inviting a user to an organization",
      example: %{
        "email" => "jane@person.com",
        "role" => "manage"
      },
      properties: %{
        email: %Schema{type: :string},
        role: %Schema{enum: ["admin", "manage", "view"], type: :string}
      },
      required: [:email, :role],
      type: :object
    })
  end

  defmodule OrgUserUpdateRequest do
    OpenApiSpex.schema(%{
      description: "POST body for updating a users organization membership",
      example: %{
        "role" => "manage"
      },
      properties: %{
        role: %Schema{enum: ["admin", "manage", "view"], type: :string}
      },
      required: [:role],
      type: :object
    })
  end
end

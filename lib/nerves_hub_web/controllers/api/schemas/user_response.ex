defmodule NervesHubWeb.API.Schemas.UserResponse do
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule User do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      # The title is optional. It defaults to the last section of the module name.
      # So the derived title for MyApp.User is "User".
      title: "User",
      description: "A registered user",
      type: :object,
      properties: %{
        id: %Schema{type: :integer, description: "User ID"},
        name: %Schema{
          type: :string,
          description: "Users name",
          pattern: ~r/[a-zA-Z][a-zA-Z0-9_]+/
        },
        email: %Schema{type: :string, description: "Email address", format: :email},
        inserted_at: %Schema{
          type: :string,
          description: "Creation timestamp",
          format: :"date-time"
        },
        updated_at: %Schema{type: :string, description: "Update timestamp", format: :"date-time"}
      },
      required: [:name, :email],
      example: %{
        "id" => 123,
        "name" => "Jane User",
        "email" => "jane@iot-company.com",
        "inserted_at" => "2017-09-12T12:34:55Z",
        "updated_at" => "2017-09-13T10:11:12Z"
      }
    })
  end

  OpenApiSpex.schema(%{
    title: "UserResponse",
    description: "Response schema for single user",
    type: :object,
    properties: %{
      data: User
    },
    example: %{
      "data" => %{
        "id" => 123,
        "name" => "Jane User",
        "email" => "jane@iot-company.com",
        "inserted_at" => "2017-09-12T12:34:55Z",
        "updated_at" => "2017-09-13T10:11:12Z"
      }
    }
  })
end

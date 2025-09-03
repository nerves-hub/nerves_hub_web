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
        email: %Schema{description: "Email address", format: :email, type: :string},
        id: %Schema{description: "User ID", type: :integer},
        inserted_at: %Schema{
          description: "Creation timestamp",
          format: :"date-time",
          type: :string
        },
        name: %Schema{
          description: "Users name",
          pattern: ~r/[a-zA-Z][a-zA-Z0-9_]+/,
          type: :string
        },
        updated_at: %Schema{description: "Update timestamp", format: :"date-time", type: :string}
      },
      required: [:name, :email],
      example: %{
        "email" => "jane@iot-company.com",
        "id" => 123,
        "inserted_at" => "2017-09-12T12:34:55Z",
        "name" => "Jane User",
        "updated_at" => "2017-09-13T10:11:12Z"
      }
    })
  end

  OpenApiSpex.schema(%{
    description: "Response schema for single user",
    example: %{
      "data" => %{
        "email" => "jane@iot-company.com",
        "id" => 123,
        "inserted_at" => "2017-09-12T12:34:55Z",
        "name" => "Jane User",
        "updated_at" => "2017-09-13T10:11:12Z"
      }
    },
    properties: %{
      data: User
    },
    title: "UserResponse",
    type: :object
  })
end

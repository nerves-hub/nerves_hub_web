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
        name: %Schema{
          type: :string,
          description: "Users name",
          pattern: ~r/[a-zA-Z][a-zA-Z0-9_]+/
        },
        email: %Schema{type: :string, description: "Email address", format: :email}
      },
      required: [:name, :email],
      example: %{
        "name" => "Jane User",
        "email" => "jane@iot-company.com"
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
        "name" => "Jane User",
        "email" => "jane@iot-company.com"
      }
    }
  })
end

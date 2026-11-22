defmodule NervesHubWeb.API.Schemas.UserTokenResponse do
  alias NervesHubWeb.API.Schemas.UserResponse.User
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "UserTokenResponse",
    description: "The user who signed in, and the API token created for them",
    type: :object,
    properties: %{
      data: %Schema{
        allOf: [
          User,
          %Schema{
            type: :object,
            properties: %{
              token: %Schema{
                type: :string,
                description: "A new user API token, sent as `Authorization: Bearer <token>`. It is only returned here."
              }
            },
            required: [:token]
          }
        ]
      }
    },
    example: %{
      "data" => %{
        "name" => "Jane User",
        "email" => "jane@iot-company.com",
        "token" => "nhu_Bf8KtQ3oZ2a6Lr1x9WcYgN4pVe7uHm0sJd5x"
      }
    }
  })
end

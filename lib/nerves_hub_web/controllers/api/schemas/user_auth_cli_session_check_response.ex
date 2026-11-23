defmodule NervesHubWeb.API.Schemas.UserAuthCLISessionStatusResponse do
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule CLISessionStatus do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "CLISessionStatus",
      description: "CLI auth exchange session status",
      type: :object,
      properties: %{
        status: %Schema{
          type: :string,
          enum: ["waiting", "ready", "collected"],
          description: """
          `waiting` until someone signed in confirms the login. `ready` once, carrying
          `user_token`. `collected` on every poll after that: the token was already
          handed out, so stop polling and start another login if it never arrived.
          """
        },
        user_token: %Schema{type: :string, description: "The API token, only while the status is `ready`"}
      },
      required: [:status],
      example: %{
        "status" => "ready",
        "user_token" => "nhu_aaabbbccc123"
      }
    })
  end

  OpenApiSpex.schema(%{
    title: "UserAuthCLISessionStatusResponse",
    description: "Response for checking the status of a CLI auth exchange session",
    type: :object,
    properties: %{
      data: CLISessionStatus
    },
    example: %{
      "data" => %{
        "status" => "ready",
        "user_token" => "nhu_aaabbbccc123"
      }
    }
  })
end

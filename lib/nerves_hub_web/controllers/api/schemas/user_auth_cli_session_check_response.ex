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
        status: %Schema{type: :string, description: "status of the auth exchange"},
        user_token: %Schema{type: :string, description: "user auth token"}
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

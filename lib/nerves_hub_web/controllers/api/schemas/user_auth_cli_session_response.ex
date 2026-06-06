defmodule NervesHubWeb.API.Schemas.UserAuthCLISessionResponse do
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule CLISession do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "CLISession",
      description: "A new CLI auth exchange session",
      type: :object,
      properties: %{
        token: %Schema{type: :string, description: "Auth token"},
        url: %Schema{type: :string, description: "URL to complete the auth exchange"}
      },
      required: [:token, :url],
      example: %{
        "token" => "218ed524-eb74-47d7-aedc-11e386961b72",
        "url" => "https://manage.nervescloud.com/auth/cli/218ed524-eb74-47d7-aedc-11e386961b72"
      }
    })
  end

  OpenApiSpex.schema(%{
    title: "UserAuthCLISessionResponse",
    description: "Response for authenticating a new CLI session",
    type: :object,
    properties: %{
      data: CLISession
    },
    example: %{
      "data" => %{
        "token" => "218ed524-eb74-47d7-aedc-11e386961b72",
        "url" => "https://manage.nervescloud.com/auth/cli/218ed524-eb74-47d7-aedc-11e386961b72"
      }
    }
  })
end

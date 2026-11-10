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
        token: %Schema{
          type: :string,
          description: "Secret the CLI polls the session with. Whoever holds it collects the login's API token."
        },
        confirmation_code: %Schema{
          type: :integer,
          description: "Eight-digit code the user types in at `url` to confirm the login"
        },
        url: %Schema{type: :string, description: "Page where the user enters the confirmation code"}
      },
      required: [:token, :url],
      example: %{
        "token" => "218ed524-eb74-47d7-aedc-11e386961b72",
        "confirmation_code" => 31_281_247,
        "url" => "https://manage.nervescloud.com/auth/cli"
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
        "confirmation_code" => 31_281_247,
        "url" => "https://manage.nervescloud.com/auth/cli"
      }
    }
  })
end

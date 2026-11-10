defmodule NervesHubWeb.API.Schemas.UserAuthCLISessionRequest do
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "UserAuthCLISessionRequest",
    description: "POST body for authenticating a user via CLI session",
    type: :object,
    properties: %{
      note: %Schema{
        type: :string,
        maxLength: 255,
        description:
          "Labels the API token the login ends with, and is shown to whoever confirms it. No control or formatting characters."
      }
    },
    example: %{
      "note" => "nerves_hub_cli 2.0.0"
    }
  })
end

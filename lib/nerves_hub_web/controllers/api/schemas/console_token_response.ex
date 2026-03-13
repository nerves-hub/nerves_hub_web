defmodule NervesHubWeb.API.Schemas.ConsoleTokenResponse do
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "ConsoleTokenResponse",
    description: "Response containing a token for websocket authentication",
    type: :object,
    properties: %{
      data: %Schema{
        type: :object,
        properties: %{
          token: %Schema{type: :string, description: "Phoenix.Token for UserSocket connection"}
        },
        required: [:token]
      }
    },
    example: %{
      "data" => %{
        "token" => "SFMyNTY.g2gDYQ..."
      }
    }
  })
end

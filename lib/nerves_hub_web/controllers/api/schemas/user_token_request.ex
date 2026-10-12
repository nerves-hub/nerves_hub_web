defmodule NervesHubWeb.API.Schemas.UserTokenRequest do
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "UserTokenRequest",
    description: "POST body for creating an API token",
    type: :object,
    properties: %{
      note: %Schema{type: :string, description: "What the token is for, shown on your account page"}
    },
    example: %{
      "note" => "nerves_hub_cli on jane-laptop"
    }
  })
end

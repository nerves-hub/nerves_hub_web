defmodule NervesHubWeb.API.Schemas.UserAuthCLISessionRequest do
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "UserAuthCLISessionRequest",
    description: "POST body for authenticating a user via CLI session",
    type: :object,
    properties: %{
      note: %Schema{type: :string}
    },
    example: %{
      "note" => "nerves_hub_cli 2.0.0"
    }
  })
end

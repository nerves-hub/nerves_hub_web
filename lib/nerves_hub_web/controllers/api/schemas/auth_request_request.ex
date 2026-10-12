defmodule NervesHubWeb.API.Schemas.AuthRequestRequest do
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "AuthRequestRequest",
    description: "POST body describing an API request to be approved by a user in their browser",
    type: :object,
    properties: %{
      method: %Schema{type: :string, enum: ["GET", "POST", "PUT", "PATCH", "DELETE"]},
      path: %Schema{type: :string, description: "An API path, starting with /api/, with any query string"},
      body: %Schema{type: :object, description: "The JSON body to send, if any"},
      note: %Schema{type: :string, description: "Shown to the person approving, labelled as provided by you"}
    },
    required: [:method, :path],
    example: %{
      "method" => "POST",
      "path" => "/api/users/me/tokens",
      "body" => %{"note" => "nerves_hub_cli on jane-laptop"},
      "note" => "nerves_hub_cli 3.2.0"
    }
  })
end

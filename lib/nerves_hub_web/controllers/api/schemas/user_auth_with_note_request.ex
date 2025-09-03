defmodule NervesHubWeb.API.Schemas.UserAuthWithNoteRequest do
  alias OpenApiSpex.Schema
  require OpenApiSpex

  OpenApiSpex.schema(%{
    description: "POST body for authenticating a user",
    example: %{
      "email" => "jane@iot-company.com",
      "note" => "Local automation",
      "password" => "my-secure-password"
    },
    properties: %{
      email: %Schema{type: :string},
      note: %Schema{type: :string},
      password: %Schema{type: :string}
    },
    required: [:email, :password],
    title: "UserAuthRequest",
    type: :object
  })
end

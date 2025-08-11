defmodule NervesHubWeb.API.Schemas.UserAuthWithNoteRequest do
  alias OpenApiSpex.Schema
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "UserAuthRequest",
    description: "POST body for authenticating a user",
    type: :object,
    properties: %{
      email: %Schema{type: :string},
      password: %Schema{type: :string},
      note: %Schema{type: :string}
    },
    required: [:email, :password],
    example: %{
      "email" => "jane@iot-company.com",
      "password" => "my-secure-password",
      "note" => "Local automation"
    }
  })
end

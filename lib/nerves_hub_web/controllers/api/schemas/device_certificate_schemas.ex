defmodule NervesHubWeb.API.Schemas.DeviceCertificateSchemas do
  alias OpenApiSpex.Schema
  require OpenApiSpex

  defmodule DeviceCertificateAuthRequest do
    OpenApiSpex.schema(%{
      description: "POST body for testing certificate auth for a Device",
      example: %{
        "certificate" => "Base64 encoded certificate"
      },
      properties: %{
        certificate: %Schema{type: :string}
      },
      required: [:certificate],
      type: :object
    })
  end
end

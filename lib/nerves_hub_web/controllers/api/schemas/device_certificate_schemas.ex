defmodule NervesHubWeb.API.Schemas.DeviceCertificateSchemas do
  alias OpenApiSpex.Schema
  require OpenApiSpex

  defmodule DeviceCertificateAuthRequest do
    OpenApiSpex.schema(%{
      description: "POST body for testing certificate auth for a Device",
      type: :object,
      properties: %{
        certificate: %Schema{type: :string}
      },
      required: [:certificate],
      example: %{
        "certificate" => "Base64 encoded certificate"
      }
    })
  end
end

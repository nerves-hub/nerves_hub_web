defmodule NervesHubWeb.API.Schemas.DeviceCertificateSchemas do
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule DeviceCertificate do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        serial: %Schema{type: :string},
        not_before: %Schema{type: :string},
        not_after: %Schema{type: :string}
      },
      example: %{
        "not_after" => "2052-12-15T21:00:00Z",
        "not_before" => "2022-12-15T20:00:00Z",
        "serial" => "123456789101112"
      }
    })
  end

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

  defmodule DeviceCertificateCreateRequest do
    OpenApiSpex.schema(%{
      description: "POST body for creating a Certificate for a Device",
      type: :object,
      properties: %{
        cert: %Schema{type: :string, description: "Base64 encoded certificate"}
      },
      required: [:cert],
      example: %{
        "cert" => "[Base64 encoded certificate]=="
      }
    })
  end

  defmodule DeviceCertificateListResponse do
    OpenApiSpex.schema(%{
      description: "Device Certificate list response",
      type: :object,
      properties: %{
        data: %Schema{description: "The device certificates details", type: :array, items: DeviceCertificate}
      },
      example: %{
        "data" => [
          %{
            "not_after" => "2052-12-15T21:00:00Z",
            "not_before" => "2022-12-15T20:00:00Z",
            "serial" => "123456789101112"
          },
          %{
            "not_after" => "2052-12-15T21:00:00Z",
            "not_before" => "2022-12-15T20:00:00Z",
            "serial" => "123456789202122"
          }
        ]
      }
    })
  end

  defmodule DeviceCertificateShowResponse do
    OpenApiSpex.schema(%{
      description: "Device Certificate show response",
      type: :object,
      properties: %{
        data: DeviceCertificate
      },
      example: %{
        "data" => %{
          "not_after" => "2052-12-15T21:00:00Z",
          "not_before" => "2022-12-15T20:00:00Z",
          "serial" => "123456789101112"
        }
      }
    })
  end
end

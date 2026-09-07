defmodule NervesHubWeb.API.Schemas.FirmwareSchemas do
  alias NervesHubWeb.API.Schemas.ErrorSchemas.ChangesetErrorResponse
  alias NervesHubWeb.API.Schemas.ErrorSchemas.ErrorResponse
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule Firmware do
    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        uuid: %Schema{type: :string, format: :uuid},
        version: %Schema{type: :string},
        architecture: %Schema{type: :string},
        platform: %Schema{type: :string},
        author: %Schema{type: :string},
        product: %Schema{type: :string, description: "Product name"},
        tool: %Schema{
          type: :string,
          description: "The update tool that handles this firmware, determined from the uploaded file",
          enum: ["fwup", "esp-idf"]
        }
      },
      example: %{
        "uuid" => "d9f8c63a-1234-5678-abcd-ef0123456789",
        "version" => "1.0.0",
        "architecture" => "arm",
        "platform" => "rpi0",
        "author" => "NervesHub",
        "product" => "MyProduct",
        "tool" => "fwup"
      }
    })
  end

  defmodule FirmwareResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for a single Firmware",
      type: :object,
      properties: %{
        data: Firmware
      },
      example: %{
        "data" => %{
          "uuid" => "d9f8c63a-1234-5678-abcd-ef0123456789",
          "version" => "1.0.0",
          "architecture" => "arm",
          "platform" => "rpi0",
          "author" => "NervesHub",
          "product" => "MyProduct",
          "tool" => "fwup"
        }
      }
    })
  end

  defmodule FirmwareUploadErrorResponse do
    OpenApiSpex.schema(%{
      description: """
      Upload failure.

      Changeset failures (a duplicate UUID, say) are keyed by field. Failures
      raised before the changeset — an unrecognised format, a format this
      product does not accept, an unsigned image, a version that is not SemVer —
      carry a single `detail` message instead.
      """,
      type: :object,
      oneOf: [
        ChangesetErrorResponse,
        ErrorResponse
      ],
      example: %{
        "errors" => %{
          "detail" =>
            "This ESP-IDF image is not signed. Sign it with `espsecure.py sign_data --version 2` and register the matching public key against your organization, or allow unsigned images in this product's settings."
        }
      }
    })
  end

  defmodule FirmwareListResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for multiple Firmwares",
      type: :object,
      properties: %{
        data: %Schema{
          description: "The Firmware details",
          type: :array,
          items: Firmware
        }
      },
      example: %{
        "data" => [
          %{
            "uuid" => "d9f8c63a-1234-5678-abcd-ef0123456789",
            "version" => "1.0.0",
            "architecture" => "arm",
            "platform" => "rpi0",
            "author" => "NervesHub",
            "product" => "MyProduct"
          }
        ]
      }
    })
  end
end

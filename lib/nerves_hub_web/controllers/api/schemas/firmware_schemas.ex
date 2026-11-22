defmodule NervesHubWeb.API.Schemas.FirmwareSchemas do
  alias NervesHubWeb.API.OpenAPI.SchemaHelpers
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
        author: %Schema{type: :string, nullable: true},
        product: %Schema{type: :string, description: "Product name"},
        tool: %Schema{
          type: :string,
          description: "The update tool that handles this firmware, determined from the uploaded file",
          enum: ["fwup", "esp-idf", "atomvm", "rauc"]
        },
        description: %Schema{type: :string, nullable: true},
        misc: %Schema{type: :string, nullable: true},
        vcs_identifier: %Schema{type: :string, nullable: true},
        size: %Schema{type: :integer, description: "Size in bytes"},
        inserted_at: SchemaHelpers.naive_timestamp("When it was created")
      },
      example: %{
        "uuid" => "d9f8c63a-1234-5678-abcd-ef0123456789",
        "version" => "1.0.0",
        "architecture" => "arm",
        "platform" => "rpi0",
        "author" => "NervesHub",
        "product" => "MyProduct",
        "tool" => "fwup",
        "description" => "Main firmware",
        "misc" => nil,
        "vcs_identifier" => "a1b2c3d",
        "size" => 104_857_600,
        "inserted_at" => "2026-01-15T09:34:27"
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
          "tool" => "fwup",
          "description" => "Main firmware",
          "misc" => nil,
          "vcs_identifier" => "a1b2c3d",
          "size" => 104_857_600,
          "inserted_at" => "2026-01-15T09:34:27"
        }
      }
    })
  end

  defmodule FirmwareUploadRequest do
    OpenApiSpex.schema(%{
      description: "The firmware file, sent as the `firmware` field of a multipart form",
      type: :object,
      properties: %{
        firmware: %Schema{
          type: :string,
          format: :binary,
          description:
            "An fwup archive (`.fw`), ESP-IDF image (`.bin`), AtomVM packbeam (`.avm`) or RAUC bundle (`.raucb`)"
        }
      },
      required: [:firmware]
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
        "data" => [Firmware.schema().example]
      }
    })
  end
end

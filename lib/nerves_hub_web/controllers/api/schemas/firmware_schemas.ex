defmodule NervesHubWeb.API.Schemas.FirmwareSchemas do
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
        product: %Schema{type: :string, description: "Product name"}
      },
      example: %{
        "uuid" => "d9f8c63a-1234-5678-abcd-ef0123456789",
        "version" => "1.0.0",
        "architecture" => "arm",
        "platform" => "rpi0",
        "author" => "NervesHub",
        "product" => "MyProduct"
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
          "product" => "MyProduct"
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

defmodule NervesHubWeb.API.Schemas.ProductSchemas do
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule Product do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        name: %Schema{
          type: :string,
          pattern: ~r/[a-zA-Z][a-zA-Z0-9_]+/
        },
        require_unique_firmware_version: %Schema{
          type: :boolean,
          description:
            "Reject uploaded firmware whose version already exists for this product's platform and architecture."
        },
        allowed_update_tools: %Schema{
          type: :array,
          items: %Schema{type: :string, enum: ["fwup", "esp-idf"]},
          description: """
          The firmware formats this product accepts. `fwup` is always present.

          A format also has to be enabled for the instance before a product can
          list it — see the ESP-IDF support documentation.
          """
        },
        allow_unsigned_esp_idf_firmware: %Schema{
          type: :boolean,
          description: """
          Accept ESP-IDF images that carry no Secure Boot v2 signature block.

          This excuses a missing signature and nothing else: an image that does
          carry a signature is always verified against the organization's
          registered signing keys.
          """
        }
      },
      example: %{
        "name" => "Example Product",
        "require_unique_firmware_version" => true,
        "allowed_update_tools" => ["fwup"],
        "allow_unsigned_esp_idf_firmware" => false
      }
    })
  end

  defmodule ProductShowResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for a single Product",
      type: :object,
      properties: %{
        data: Product
      },
      example: %{
        "data" => %{
          "name" => "Example Product",
          "require_unique_firmware_version" => true,
          "allowed_update_tools" => ["fwup"],
          "allow_unsigned_esp_idf_firmware" => false
        }
      }
    })
  end

  defmodule ProductListResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for multiple products",
      type: :object,
      properties: %{
        data: %Schema{description: "The products details", type: :array, items: Product}
      },
      example: %{
        "data" => [
          %{
            "name" => "Example Product",
            "require_unique_firmware_version" => true,
            "allowed_update_tools" => ["fwup"],
            "allow_unsigned_esp_idf_firmware" => false
          },
          %{
            "name" => "Another Example Product",
            "require_unique_firmware_version" => true,
            "allowed_update_tools" => ["fwup", "esp-idf"],
            "allow_unsigned_esp_idf_firmware" => true
          }
        ]
      }
    })
  end

  defmodule ProductCreationRequest do
    OpenApiSpex.schema(%{
      description: "POST body for creating a product",
      type: :object,
      properties: %{
        product: %Schema{
          properties: %{
            name: %Schema{type: :string}
          },
          required: [:name]
        }
      },
      required: [:product],
      example: %{
        "product" => %{
          "name" => "ExampleProduct"
        }
      }
    })
  end

  defmodule ProductUpdateRequest do
    OpenApiSpex.schema(%{
      description: """
      PUT body for updating a product's settings.

      Every field is optional; only the ones sent are changed. A product cannot
      be renamed here — its name is its identifier in every URL — and sending
      any field not listed below is an error rather than being ignored.
      """,
      type: :object,
      properties: %{
        require_unique_firmware_version: %Schema{type: :boolean},
        allowed_update_tools: %Schema{
          type: :array,
          items: %Schema{type: :string, enum: ["fwup", "esp-idf"]}
        },
        allow_unsigned_esp_idf_firmware: %Schema{type: :boolean}
      },
      example: %{
        "allowed_update_tools" => ["fwup", "esp-idf"],
        "allow_unsigned_esp_idf_firmware" => true
      }
    })
  end
end

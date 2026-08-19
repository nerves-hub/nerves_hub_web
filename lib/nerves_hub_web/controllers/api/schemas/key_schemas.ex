defmodule NervesHubWeb.API.Schemas.KeySchemas do
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule SigningKey do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        name: %Schema{type: :string},
        key: %Schema{type: :string},
        scheme: %Schema{
          type: :string,
          description: "Signature scheme this key belongs to",
          enum: ["ed25519", "secure_boot_v2_rsa"]
        }
      },
      example: %{
        "name" => "CI",
        "key" => "abc123=",
        "scheme" => "ed25519"
      }
    })
  end

  defmodule SigningKeyIndexResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for multiple Signing Keys",
      type: :object,
      properties: %{
        data: %Schema{description: "The Signing Key details", type: :array, items: SigningKey}
      },
      example: %{
        "data" => [
          %{
            "name" => "QA",
            "key" => "abc123=",
            "scheme" => "ed25519"
          },
          %{
            "name" => "ESP release",
            "key" => "-----BEGIN PUBLIC KEY-----\nMIIBoj...\n-----END PUBLIC KEY-----\n",
            "scheme" => "secure_boot_v2_rsa"
          }
        ]
      }
    })
  end

  defmodule SigningKeyShowResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for a single Signing Key",
      type: :object,
      properties: %{
        data: SigningKey
      },
      example: %{
        "data" => %{
          "name" => "QA",
          "key" => "abc123=",
          "scheme" => "ed25519"
        }
      }
    })
  end

  defmodule SigningKeyCreationRequest do
    OpenApiSpex.schema(%{
      description: """
      POST body for adding a Signing Key to an Organization.

      `scheme` defaults to `ed25519` when omitted, which is what every key was
      before ESP-IDF support — so existing clients keep working unchanged.
      """,
      type: :object,
      properties: %{
        name: %Schema{type: :string},
        key: %Schema{type: :string},
        scheme: %Schema{
          type: :string,
          description: "Signature scheme this key belongs to",
          enum: ["ed25519", "secure_boot_v2_rsa"]
        }
      },
      required: [:name, :key],
      example: %{
        "name" => "ESP release",
        "key" => "-----BEGIN PUBLIC KEY-----\nMIIBoj...\n-----END PUBLIC KEY-----\n",
        "scheme" => "secure_boot_v2_rsa"
      }
    })
  end
end

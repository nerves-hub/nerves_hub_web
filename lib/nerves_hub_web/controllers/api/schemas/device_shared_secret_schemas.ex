defmodule NervesHubWeb.API.Schemas.DeviceSharedSecretSchemas do
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule DeviceSharedSecret do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      description: "A device's shared secret, without the secret itself",
      type: :object,
      properties: %{
        key: %Schema{type: :string, description: "The key the device sends as `x-nh-key`"},
        deactivated_at: %Schema{
          type: :string,
          format: :"date-time",
          nullable: true,
          description: "When the secret was deactivated, or null while it is active"
        },
        inserted_at: %Schema{type: :string, format: :"date-time"}
      },
      example: %{
        "key" => "nhd_[43 URL-safe characters]",
        "deactivated_at" => nil,
        "inserted_at" => "2026-10-08T12:00:00Z"
      }
    })
  end

  defmodule DeviceSharedSecretWithSecret do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      description: "A newly created device shared secret. The secret is only returned once, in this response.",
      type: :object,
      properties: %{
        key: %Schema{type: :string, description: "The key the device sends as `x-nh-key`"},
        secret: %Schema{type: :string, description: "The secret the device signs its connection with"},
        deactivated_at: %Schema{type: :string, format: :"date-time", nullable: true},
        inserted_at: %Schema{type: :string, format: :"date-time"}
      },
      example: %{
        "key" => "nhd_[43 URL-safe characters]",
        "secret" => "[43 random characters]",
        "deactivated_at" => nil,
        "inserted_at" => "2026-10-08T12:00:00Z"
      }
    })
  end

  defmodule DeviceSharedSecretListResponse do
    OpenApiSpex.schema(%{
      description: "Device shared secret list response",
      type: :object,
      properties: %{
        data: %Schema{
          description: "Every shared secret the device has been given, deactivated ones included",
          type: :array,
          items: DeviceSharedSecret
        }
      }
    })
  end

  defmodule DeviceSharedSecretCreateResponse do
    OpenApiSpex.schema(%{
      description: "Device shared secret create response",
      type: :object,
      properties: %{
        data: DeviceSharedSecretWithSecret
      }
    })
  end
end

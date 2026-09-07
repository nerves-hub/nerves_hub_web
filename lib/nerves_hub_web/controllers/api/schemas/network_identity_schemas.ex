defmodule NervesHubWeb.API.Schemas.NetworkIdentitySchemas do
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule NetworkIdentity do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      description: "A key a device holds on a network NervesHub does not run",
      type: :object,
      properties: %{
        identifier: %Schema{
          type: :string,
          description: "The value possession of which is proven — a public key, not a handle that can be reassigned"
        },
        service: %Schema{
          type: :string,
          description: "The protocol",
          enum: ["iroh", "netbird", "tailscale", "wireguard"]
        },
        instance: %Schema{
          type: :string,
          description: "Which endpoint of that protocol. `default` for anything running a single one"
        },
        source: %Schema{
          type: :string,
          description:
            "Whether anything proved this key. `device_reported` means a device did; `operator` means it was typed in",
          enum: ["device_reported", "operator"]
        },
        details: %Schema{
          type: :object,
          description: "Per-service and non-authoritative — relay urls, an assigned address. Never a secret",
          additionalProperties: true
        },
        last_reported_at: %Schema{type: :string, format: :"date-time", nullable: true},
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      example: %{
        "identifier" => "c8924b6c9b7a8528b1365ebec4b2e43b6edebef684f8521f12b8caaf6e1b2302",
        "service" => "iroh",
        "instance" => "default",
        "source" => "device_reported",
        "details" => %{"relay" => "https://relay.example.com"},
        "last_reported_at" => "2026-08-16T09:14:00Z",
        "inserted_at" => "2026-08-14T11:02:31Z",
        "updated_at" => "2026-08-16T09:14:00Z"
      }
    })
  end

  defmodule NetworkIdentityListResponse do
    OpenApiSpex.schema(%{
      description: "Network Identity list response",
      type: :object,
      properties: %{
        data: %Schema{description: "The identities this device holds", type: :array, items: NetworkIdentity}
      },
      example: %{
        "data" => [
          %{
            "identifier" => "c8924b6c9b7a8528b1365ebec4b2e43b6edebef684f8521f12b8caaf6e1b2302",
            "service" => "iroh",
            "instance" => "default",
            "source" => "device_reported",
            "details" => %{"relay" => "https://relay.example.com"},
            "last_reported_at" => "2026-08-16T09:14:00Z",
            "inserted_at" => "2026-08-14T11:02:31Z",
            "updated_at" => "2026-08-16T09:14:00Z"
          },
          %{
            "identifier" => "5f691e39f55415be337b2e4cc0dd7291586ab7c4356bf32bab60f46fc78f95d5",
            "service" => "iroh",
            "instance" => "console",
            "source" => "device_reported",
            "details" => %{},
            "last_reported_at" => "2026-08-16T09:14:00Z",
            "inserted_at" => "2026-08-14T11:02:31Z",
            "updated_at" => "2026-08-16T09:14:00Z"
          }
        ]
      }
    })
  end
end

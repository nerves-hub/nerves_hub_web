defmodule NervesHubWeb.API.Schemas.IrohEndpointSchemas do
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule IrohEndpointOwner do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      description: "What holds this endpoint id",
      type: :object,
      properties: %{
        type: %Schema{
          type: :string,
          description:
            "`device` for one a device proved, `user` for a member's own machine, `none` for one the organization holds directly",
          enum: ["device", "user", "none"]
        },
        device_identifier: %Schema{type: :string, nullable: true, description: "Set when `type` is `device`"},
        user_name: %Schema{type: :string, nullable: true, description: "Set when `type` is `user`"},
        user_email: %Schema{type: :string, nullable: true, description: "Set when `type` is `user`"}
      },
      example: %{
        "type" => "device",
        "device_identifier" => "example_device",
        "user_name" => nil,
        "user_email" => nil
      }
    })
  end

  defmodule IrohEndpoint do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      description: "An iroh endpoint id registered to an organization",
      type: :object,
      properties: %{
        identifier: %Schema{type: :string, description: "The endpoint id — 64 hex characters"},
        service: %Schema{type: :string, enum: ["iroh"]},
        instance: %Schema{
          type: :string,
          description: "Which endpoint of iroh this is. `default` for anything running a single one"
        },
        source: %Schema{
          type: :string,
          description: "`device_reported` means a device proved this key; `operator` means it was registered by hand",
          enum: ["device_reported", "operator"]
        },
        details: %Schema{type: :object, additionalProperties: true},
        last_reported_at: %Schema{type: :string, format: :"date-time", nullable: true},
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"},
        owner: IrohEndpointOwner
      },
      example: %{
        "identifier" => "c8924b6c9b7a8528b1365ebec4b2e43b6edebef684f8521f12b8caaf6e1b2302",
        "service" => "iroh",
        "instance" => "default",
        "source" => "device_reported",
        "details" => %{},
        "last_reported_at" => "2026-08-16T09:14:00Z",
        "inserted_at" => "2026-08-14T11:02:31Z",
        "updated_at" => "2026-08-16T09:14:00Z",
        "owner" => %{
          "type" => "device",
          "device_identifier" => "example_device",
          "user_name" => nil,
          "user_email" => nil
        }
      }
    })
  end

  defmodule IrohEndpointCreateRequest do
    OpenApiSpex.schema(%{
      description: "POST body for registering an Iroh Endpoint against an Organization",
      type: :object,
      properties: %{
        identifier: %Schema{
          type: :string,
          description: "The endpoint id — the public key the endpoint proves it holds, not a ticket or a relay url"
        },
        instance: %Schema{
          type: :string,
          description: "Names which endpoint this is, for something running more than one. Omit for a single one",
          default: "default"
        },
        user_email: %Schema{
          type: :string,
          description:
            "Attach the endpoint to this member of the organization — their laptop, say. Omit for one the organization holds directly, or for a device that will claim it on its next connection. The address must belong to a member",
          nullable: true
        },
        details: %Schema{
          type: :object,
          description: "Anything worth recording alongside the key. Non-authoritative, and never a secret",
          additionalProperties: true
        }
      },
      required: [:identifier],
      example: %{
        "identifier" => "c8924b6c9b7a8528b1365ebec4b2e43b6edebef684f8521f12b8caaf6e1b2302",
        "instance" => "console",
        "user_email" => "member@example.com"
      }
    })
  end

  defmodule IrohEndpointListResponse do
    OpenApiSpex.schema(%{
      description: "Iroh Endpoint list response",
      type: :object,
      properties: %{
        data: %Schema{description: "The organization's iroh endpoint ids", type: :array, items: IrohEndpoint}
      },
      example: %{
        "data" => [
          %{
            "identifier" => "c8924b6c9b7a8528b1365ebec4b2e43b6edebef684f8521f12b8caaf6e1b2302",
            "service" => "iroh",
            "instance" => "default",
            "source" => "device_reported",
            "details" => %{},
            "last_reported_at" => "2026-08-16T09:14:00Z",
            "inserted_at" => "2026-08-14T11:02:31Z",
            "updated_at" => "2026-08-16T09:14:00Z",
            "owner" => %{
              "type" => "device",
              "device_identifier" => "example_device",
              "user_name" => nil,
              "user_email" => nil
            }
          },
          %{
            "identifier" => "5f691e39f55415be337b2e4cc0dd7291586ab7c4356bf32bab60f46fc78f95d5",
            "service" => "iroh",
            "instance" => "default",
            "source" => "operator",
            "details" => %{},
            "last_reported_at" => nil,
            "inserted_at" => "2026-08-15T08:41:12Z",
            "updated_at" => "2026-08-15T08:41:12Z",
            "owner" => %{
              "type" => "user",
              "device_identifier" => nil,
              "user_name" => "Alex Doe",
              "user_email" => "member@example.com"
            }
          }
        ]
      }
    })
  end

  defmodule IrohEndpointShowResponse do
    OpenApiSpex.schema(%{
      description: "Iroh Endpoint show response",
      type: :object,
      properties: %{data: IrohEndpoint},
      example: %{
        "data" => %{
          "identifier" => "c8924b6c9b7a8528b1365ebec4b2e43b6edebef684f8521f12b8caaf6e1b2302",
          "service" => "iroh",
          "instance" => "default",
          "source" => "device_reported",
          "details" => %{},
          "last_reported_at" => "2026-08-16T09:14:00Z",
          "inserted_at" => "2026-08-14T11:02:31Z",
          "updated_at" => "2026-08-16T09:14:00Z",
          "owner" => %{
            "type" => "device",
            "device_identifier" => "example_device",
            "user_name" => nil,
            "user_email" => nil
          }
        }
      }
    })
  end
end

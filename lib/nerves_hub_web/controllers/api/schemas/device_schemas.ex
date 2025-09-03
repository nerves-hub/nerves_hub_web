defmodule NervesHubWeb.API.Schemas.DeviceSchemas do
  alias OpenApiSpex.Schema
  require OpenApiSpex

  defmodule Device do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      example: %{
        "connection_status" => "connected",
        "deployment_group" => %{
          "firmware_uuid" => "6fd2bbc8-52b8-4826-5c2a-189968d0de23",
          "firmware_version" => "1.2.3",
          "is_active" => true,
          "name" => "Prod Deployment"
        },
        "description" => "A great device",
        "firmware_metadata" => %{
          "architecture" => "arm",
          "author" => "",
          "description" => "Prod Firmware",
          "fwup_version" => "1.10.1",
          "id" => "3f2264c3-cc52-2ba9-b77d-e441f8bb91b6",
          "misc" => "extra comments",
          "platform" => "rpi5",
          "product" => "AmazingProduct",
          "uuid" => "6fd2bbc8-52b8-4826-5c2a-189968d0de23",
          "vcs_identifier" => "",
          "version" => "1.2.3"
        },
        "identifier" => "abc123",
        "last_communication" => "2050-04-20T00:33:09Z",
        "online" => true,
        "org_name" => "BigCompany",
        "priority_updates" => true,
        "product_name" => "AmazingProduct",
        "tags" => "prod, customerABC",
        "updates_blocked_until" => "2050-04-20T00:33:09Z",
        "updates_enabled" => true,
        "version" => "1.2.3"
      },
      properties: %{
        connection_status: %Schema{enum: ["connected", "disconnected"], type: :string},
        deployment_group: %Schema{
          properties: %{
            architecture: %Schema{type: :string},
            author: %Schema{type: :string},
            description: %Schema{type: :string},
            fwup_version: %Schema{type: :string},
            id: %Schema{type: :string},
            misc: %Schema{type: :string},
            platform: %Schema{type: :string},
            product: %Schema{type: :string},
            uuid: %Schema{type: :string},
            vcs_identifier: %Schema{type: :string},
            version: %Schema{type: :string}
          },
          type: :object
        },
        description: %Schema{type: :string},
        firmware_metadata: %Schema{
          properties: %{
            firmware_uuid: %Schema{type: :string},
            firmware_version: %Schema{type: :string},
            is_active: %Schema{type: :boolean},
            name: %Schema{type: :string}
          },
          type: :object
        },
        identifier: %Schema{type: :integer},
        last_communication: %Schema{
          deprecated: true,
          format: :"date-time",
          type: :string
        },
        online: %Schema{type: :boolean},
        org_name: %Schema{type: :string},
        priority_updates: %Schema{
          description: "Prioritizes this device for updates when part of a deployment group",
          type: :boolean
        },
        product_name: %Schema{type: :string},
        tags: %Schema{type: :string},
        updates_blocked_until: %Schema{
          description: "Device penalty box expiration timestamp",
          format: :"date-time",
          type: :string
        },
        updates_enabled: %Schema{type: :boolean},
        version: %Schema{type: :string}
      },
      type: :object
    })
  end

  defmodule DeviceListResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for multiple Devices",
      example: %{
        "data" => [
          %{
            "connection_status" => "connected",
            "deployment_group" => %{
              "firmware_uuid" => "6fd2bbc8-52b8-4826-5c2a-189968d0de23",
              "firmware_version" => "1.2.3",
              "is_active" => true,
              "name" => "Prod Deployment"
            },
            "description" => "A great device",
            "firmware_metadata" => %{
              "architecture" => "arm",
              "author" => "",
              "description" => "Prod Firmware",
              "fwup_version" => "1.10.1",
              "id" => "3f2264c3-cc52-2ba9-b77d-e441f8bb91b6",
              "misc" => "extra comments",
              "platform" => "rpi5",
              "product" => "AmazingProduct",
              "uuid" => "6fd2bbc8-52b8-4826-5c2a-189968d0de23",
              "vcs_identifier" => "",
              "version" => "1.2.3"
            },
            "identifier" => "abc123",
            "last_communication" => "2050-04-20T00:33:09Z",
            "online" => true,
            "org_name" => "BigCompany",
            "priority_updates" => true,
            "product_name" => "AmazingProduct",
            "tags" => "prod, customerABC",
            "updates_blocked_until" => "2050-04-20T00:33:09Z",
            "updates_enabled" => true,
            "version" => "1.2.3"
          },
          %{
            "connection_status" => "disconnected",
            "deployment_group" => %{
              "firmware_uuid" => "6fd2bbc8-52b8-4826-5c2a-189968d0de23",
              "firmware_version" => "1.2.3",
              "is_active" => true,
              "name" => "Prod Deployment"
            },
            "description" => "Another great device",
            "firmware_metadata" => %{
              "architecture" => "arm",
              "author" => "",
              "description" => "Prod Firmware",
              "fwup_version" => "1.10.1",
              "id" => "3f2264c3-cc52-2ba9-b77d-e441f8bb91b6",
              "misc" => "extra comments",
              "platform" => "rpi5",
              "product" => "AmazingProduct",
              "uuid" => "6fd2bbc8-52b8-4826-5c2a-189968d0de23",
              "vcs_identifier" => "",
              "version" => "1.2.3"
            },
            "identifier" => "def456",
            "last_communication" => "2050-04-20T00:33:09Z",
            "online" => false,
            "org_name" => "BigCompany",
            "priority_updates" => true,
            "product_name" => "AmazingProduct",
            "tags" => "prod, customerDEF",
            "updates_blocked_until" => "2050-04-20T00:33:09Z",
            "updates_enabled" => true,
            "version" => "1.2.3"
          }
        ]
      },
      properties: %{
        data: %Schema{
          description: "The Device schema",
          items: Device,
          type: :array
        }
      },
      type: :object
    })
  end

  defmodule DeviceCreationRequest do
    OpenApiSpex.schema(%{
      description: "POST body for creating a Device",
      example: %{
        "device" => %{
          "deployment_group_id" => 1,
          "description" => "Example Device",
          "identifier" => "abc123",
          "priority_updates" => true,
          "tags" => "prod, customerJNK",
          "updates_enabled" => false
        }
      },
      properties: %{
        device: %Schema{
          properties: %{
            deployment_group_id: %Schema{type: :integer},
            description: %Schema{type: :string},
            identifier: %Schema{type: :string},
            priority_updates: %Schema{type: :boolean},
            tags: %Schema{type: :string},
            updates_enabled: %Schema{type: :boolean}
          },
          required: [:identifier]
        }
      },
      required: [:device],
      type: :object
    })
  end

  defmodule DeviceUpdateRequest do
    OpenApiSpex.schema(%{
      description: "POST body for updating a Device",
      example: %{
        "device" => %{
          "deployment_group_id" => 1,
          "description" => "Example Device",
          "priority_updates" => true,
          "tags" => "prod, customerJNK",
          "updates_enabled" => false
        }
      },
      properties: %{
        device: %Schema{
          properties: %{
            deployment_group_id: %Schema{type: :integer},
            description: %Schema{type: :string},
            priority_updates: %Schema{type: :boolean},
            tags: %Schema{type: :string},
            updates_enabled: %Schema{type: :boolean}
          }
        }
      },
      type: :object
    })
  end
end

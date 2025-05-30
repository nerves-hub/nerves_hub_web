defmodule NervesHubWeb.API.Schemas.DeviceSchemas do
  alias OpenApiSpex.Schema
  require OpenApiSpex

  defmodule Device do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        identifier: %Schema{type: :integer},
        description: %Schema{type: :string},
        tags: %Schema{type: :string},
        online: %Schema{type: :boolean},
        connection_status: %Schema{type: :string, enum: ["connected", "disconnected"]},
        firmware_metadata: %Schema{
          type: :object,
          properties: %{
            name: %Schema{type: :string},
            is_active: %Schema{type: :boolean},
            firmware_uuid: %Schema{type: :string},
            firmware_version: %Schema{type: :string}
          }
        },
        version: %Schema{type: :string},
        deployment_group: %Schema{
          type: :object,
          properties: %{
            id: %Schema{type: :string},
            misc: %Schema{type: :string},
            uuid: %Schema{type: :string},
            author: %Schema{type: :string},
            product: %Schema{type: :string},
            version: %Schema{type: :string},
            platform: %Schema{type: :string},
            description: %Schema{type: :string},
            architecture: %Schema{type: :string},
            fwup_version: %Schema{type: :string},
            vcs_identifier: %Schema{type: :string}
          }
        },
        updates_enabled: %Schema{type: :boolean},
        updates_blocked_until: %Schema{
          type: :string,
          description: "Device penalty box expiration timestamp",
          format: :"date-time"
        },
        priority_updates: %Schema{
          type: :boolean,
          description: "Prioritizes this device for updates when part of a deployment group"
        },
        org_name: %Schema{type: :string},
        product_name: %Schema{type: :string},
        last_communication: %Schema{
          type: :string,
          format: :"date-time",
          deprecated: true
        }
      },
      example: %{
        "identifier" => "abc123",
        "description" => "A great device",
        "tags" => "prod, customerABC",
        "online" => true,
        "connection_status" => "connected",
        "firmware_metadata" => %{
          "id" => "3f2264c3-cc52-2ba9-b77d-e441f8bb91b6",
          "misc" => "extra comments",
          "uuid" => "6fd2bbc8-52b8-4826-5c2a-189968d0de23",
          "author" => "",
          "product" => "AmazingProduct",
          "version" => "1.2.3",
          "platform" => "rpi5",
          "description" => "Prod Firmware",
          "architecture" => "arm",
          "fwup_version" => "1.10.1",
          "vcs_identifier" => ""
        },
        "version" => "1.2.3",
        "deployment_group" => %{
          "firmware_uuid" => "6fd2bbc8-52b8-4826-5c2a-189968d0de23",
          "firmware_version" => "1.2.3",
          "is_active" => true,
          "name" => "Prod Deployment"
        },
        "updates_enabled" => true,
        "updates_blocked_until" => "2050-04-20T00:33:09Z",
        "priority_updates" => true,
        "org_name" => "BigCompany",
        "product_name" => "AmazingProduct",
        "last_communication" => "2050-04-20T00:33:09Z"
      }
    })
  end

  defmodule DeviceListResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for multiple Devices",
      type: :object,
      properties: %{
        data: %Schema{
          description: "The Device schema",
          type: :array,
          items: Device
        }
      },
      example: %{
        "data" => [
          %{
            "identifier" => "abc123",
            "description" => "A great device",
            "tags" => "prod, customerABC",
            "online" => true,
            "connection_status" => "connected",
            "firmware_metadata" => %{
              "id" => "3f2264c3-cc52-2ba9-b77d-e441f8bb91b6",
              "misc" => "extra comments",
              "uuid" => "6fd2bbc8-52b8-4826-5c2a-189968d0de23",
              "author" => "",
              "product" => "AmazingProduct",
              "version" => "1.2.3",
              "platform" => "rpi5",
              "description" => "Prod Firmware",
              "architecture" => "arm",
              "fwup_version" => "1.10.1",
              "vcs_identifier" => ""
            },
            "version" => "1.2.3",
            "deployment_group" => %{
              "firmware_uuid" => "6fd2bbc8-52b8-4826-5c2a-189968d0de23",
              "firmware_version" => "1.2.3",
              "is_active" => true,
              "name" => "Prod Deployment"
            },
            "updates_enabled" => true,
            "updates_blocked_until" => "2050-04-20T00:33:09Z",
            "priority_updates" => true,
            "org_name" => "BigCompany",
            "product_name" => "AmazingProduct",
            "last_communication" => "2050-04-20T00:33:09Z"
          },
          %{
            "identifier" => "def456",
            "description" => "Another great device",
            "tags" => "prod, customerDEF",
            "online" => false,
            "connection_status" => "disconnected",
            "firmware_metadata" => %{
              "id" => "3f2264c3-cc52-2ba9-b77d-e441f8bb91b6",
              "misc" => "extra comments",
              "uuid" => "6fd2bbc8-52b8-4826-5c2a-189968d0de23",
              "author" => "",
              "product" => "AmazingProduct",
              "version" => "1.2.3",
              "platform" => "rpi5",
              "description" => "Prod Firmware",
              "architecture" => "arm",
              "fwup_version" => "1.10.1",
              "vcs_identifier" => ""
            },
            "version" => "1.2.3",
            "deployment_group" => %{
              "firmware_uuid" => "6fd2bbc8-52b8-4826-5c2a-189968d0de23",
              "firmware_version" => "1.2.3",
              "is_active" => true,
              "name" => "Prod Deployment"
            },
            "updates_enabled" => true,
            "updates_blocked_until" => "2050-04-20T00:33:09Z",
            "priority_updates" => true,
            "org_name" => "BigCompany",
            "product_name" => "AmazingProduct",
            "last_communication" => "2050-04-20T00:33:09Z"
          }
        ]
      }
    })
  end

  defmodule DeviceCreationRequest do
    OpenApiSpex.schema(%{
      description: "POST body for creating a Device",
      type: :object,
      properties: %{
        device: %Schema{
          properties: %{
            identifier: %Schema{type: :string},
            description: %Schema{type: :string},
            tags: %Schema{type: :string},
            deployment_group_id: %Schema{type: :integer},
            updates_enabled: %Schema{type: :boolean},
            priority_updates: %Schema{type: :boolean}
          },
          required: [:identifier]
        }
      },
      required: [:device],
      example: %{
        "device" => %{
          "identifier" => "abc123",
          "description" => "Example Device",
          "tags" => "prod, customerJNK",
          "deployment_group_id" => 1,
          "updates_enabled" => false,
          "priority_updates" => true
        }
      }
    })
  end

  defmodule DeviceUpdateRequest do
    OpenApiSpex.schema(%{
      description: "POST body for updating a Device",
      type: :object,
      properties: %{
        device: %Schema{
          properties: %{
            description: %Schema{type: :string},
            tags: %Schema{type: :string},
            deployment_group_id: %Schema{type: :integer},
            updates_enabled: %Schema{type: :boolean},
            priority_updates: %Schema{type: :boolean}
          }
        }
      },
      example: %{
        "device" => %{
          "description" => "Example Device",
          "tags" => "prod, customerJNK",
          "deployment_group_id" => 1,
          "updates_enabled" => false,
          "priority_updates" => true
        }
      }
    })
  end
end

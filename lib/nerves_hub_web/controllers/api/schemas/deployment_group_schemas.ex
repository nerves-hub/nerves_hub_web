defmodule NervesHubWeb.API.Schemas.DeploymentGroupSchemas do
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule Firmware do
    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        version: %Schema{type: :string},
        architecture: %Schema{type: :string},
        platform: %Schema{type: :string},
        uuid: %Schema{type: :string}
      },
      example: %{
        "version" => "1.0.0",
        "architecture" => "arm",
        "platform" => "rpi0",
        "uuid" => "d9f8c63a-1234-5678-abcd-ef0123456789"
      }
    })
  end

  defmodule CurrentRelease do
    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        number: %Schema{type: :integer},
        firmware: Firmware,
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      example: %{
        "number" => 3,
        "firmware" => %{
          "version" => "1.0.0",
          "architecture" => "arm",
          "platform" => "rpi0",
          "uuid" => "d9f8c63a-1234-5678-abcd-ef0123456789"
        },
        "inserted_at" => "2024-01-01T00:00:00Z",
        "updated_at" => "2024-01-01T00:00:00Z"
      }
    })
  end

  defmodule Conditions do
    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        version: %Schema{type: :string},
        tags: %Schema{type: :array, items: %Schema{type: :string}},
        tag_operator: %Schema{
          type: :string,
          enum: ["and", "or"],
          description: ~s{How device tags are matched: "and" (require all) or "or" (allow any)},
          default: "and"
        }
      },
      example: %{
        "version" => ">= 1.0.0",
        "tags" => ["beta"],
        "tag_operator" => "and"
      }
    })
  end

  defmodule DeploymentGroup do
    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        name: %Schema{type: :string},
        is_active: %Schema{type: :boolean},
        state: %Schema{type: :string, enum: ["on", "off"]},
        firmware_uuid: %Schema{type: :string},
        current_release: CurrentRelease,
        conditions: Conditions,
        delta_updatable: %Schema{type: :boolean},
        device_count: %Schema{type: :integer},
        releases_count: %Schema{type: :integer}
      },
      example: %{
        "name" => "production",
        "is_active" => true,
        "state" => "on",
        "firmware_uuid" => "d9f8c63a-1234-5678-abcd-ef0123456789",
        "current_release" => %{
          "number" => 3,
          "firmware" => %{
            "version" => "1.0.0",
            "architecture" => "arm",
            "platform" => "rpi0",
            "uuid" => "d9f8c63a-1234-5678-abcd-ef0123456789"
          },
          "inserted_at" => "2024-01-01T00:00:00Z",
          "updated_at" => "2024-01-01T00:00:00Z"
        },
        "conditions" => %{
          "version" => ">= 1.0.0",
          "tags" => ["beta"]
        },
        "delta_updatable" => false,
        "device_count" => 42,
        "releases_count" => 3
      }
    })
  end

  defmodule DeploymentGroupListResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for multiple Deployment Groups",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: DeploymentGroup}
      }
    })
  end

  defmodule DeploymentGroupResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for a single Deployment Group",
      type: :object,
      properties: %{
        data: DeploymentGroup
      }
    })
  end

  defmodule DeploymentGroupCreationRequest do
    OpenApiSpex.schema(%{
      description: "POST body for creating a Deployment Group",
      type: :object,
      properties: %{
        name: %Schema{type: :string},
        firmware: %Schema{type: :string, description: "Firmware UUID"},
        conditions: Conditions,
        state: %Schema{type: :string, enum: ["on", "off"]},
        delta_updatable: %Schema{type: :boolean}
      },
      required: [:name, :firmware],
      example: %{
        "name" => "production",
        "firmware" => "d9f8c63a-1234-5678-abcd-ef0123456789",
        "conditions" => %{
          "version" => ">= 1.0.0",
          "tags" => ["prod"]
        },
        "state" => "on"
      }
    })
  end

  defmodule DeploymentGroupUpdateRequest do
    OpenApiSpex.schema(%{
      description: "PUT body for updating a Deployment Group",
      type: :object,
      properties: %{
        deployment: %Schema{
          type: :object,
          properties: %{
            firmware: %Schema{type: :string, description: "Firmware UUID"},
            conditions: Conditions,
            state: %Schema{type: :string, enum: ["on", "off"]},
            delta_updatable: %Schema{type: :boolean}
          }
        }
      },
      example: %{
        "deployment" => %{
          "state" => "on",
          "conditions" => %{
            "version" => ">= 1.0.0",
            "tags" => ["prod"]
          }
        }
      }
    })
  end
end

defmodule NervesHubWeb.API.Schemas.DeploymentGroupSchemas do
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule Firmware do
    require OpenApiSpex

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
    require OpenApiSpex

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
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        version: %Schema{type: :string},
        tags: %Schema{type: :array, items: %Schema{type: :string}}
      },
      example: %{
        "version" => ">= 1.0.0",
        "tags" => ["beta"]
      }
    })
  end

  defmodule DeploymentGroup do
    require OpenApiSpex

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
end

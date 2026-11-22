defmodule NervesHubWeb.API.Schemas.DeploymentGroupSchemas do
  alias NervesHubWeb.API.OpenAPI.SchemaHelpers
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule Firmware do
    # Titled apart from `FirmwareSchemas.Firmware`: the spec keys schemas by
    # title, so two called "Firmware" would leave one standing in for both.
    OpenApiSpex.schema(%{
      title: "ReleaseFirmware",
      description: "The firmware a release sends",
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
        required: %Schema{
          type: :boolean,
          description: "Devices that have not reached a required release are updated to it before any newer release"
        },
        firmware: Firmware,
        inserted_at: SchemaHelpers.naive_timestamp("When it was created"),
        updated_at: SchemaHelpers.naive_timestamp("When it was last changed")
      },
      example: %{
        "number" => 3,
        "required" => false,
        "firmware" => %{
          "version" => "1.0.0",
          "architecture" => "arm",
          "platform" => "rpi0",
          "uuid" => "d9f8c63a-1234-5678-abcd-ef0123456789"
        },
        "inserted_at" => "2024-01-01T00:00:00",
        "updated_at" => "2024-01-01T00:00:00"
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
        archive_uuid: %Schema{
          type: :string,
          description: "The UUID of the archive the current release sends with its firmware, if any",
          nullable: true
        },
        conditions: Conditions,
        delta_updatable: %Schema{type: :boolean},
        device_count: %Schema{type: :integer},
        releases_count: %Schema{type: :integer},
        notes: %Schema{
          type: :string,
          description: "Free-text notes describing why this deployment group exists",
          nullable: true
        }
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
          "inserted_at" => "2024-01-01T00:00:00",
          "updated_at" => "2024-01-01T00:00:00"
        },
        "archive_uuid" => nil,
        "conditions" => %{
          "version" => ">= 1.0.0",
          "tags" => ["beta"]
        },
        "delta_updatable" => false,
        "device_count" => 42,
        "releases_count" => 3,
        "notes" => "Rolled out for the summer campaign hardware batch"
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
        delta_updatable: %Schema{type: :boolean},
        notes: %Schema{
          type: :string,
          description: "Free-text notes describing why this deployment group is being created"
        }
      },
      required: [:name, :firmware],
      example: %{
        "name" => "production",
        "firmware" => "d9f8c63a-1234-5678-abcd-ef0123456789",
        "conditions" => %{
          "version" => ">= 1.0.0",
          "tags" => ["prod"]
        },
        "state" => "on",
        "notes" => "Rolled out for the summer campaign hardware batch"
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
            required: %Schema{
              type: :boolean,
              description:
                "Mark the release created by a firmware change as required: devices that have not reached it are updated to it before any newer release"
            },
            conditions: Conditions,
            state: %Schema{type: :string, enum: ["on", "off"]},
            delta_updatable: %Schema{type: :boolean},
            notes: %Schema{type: :string, description: "Free-text notes describing why this deployment group exists"}
          }
        }
      },
      example: %{
        "deployment" => %{
          "state" => "on",
          "conditions" => %{
            "version" => ">= 1.0.0",
            "tags" => ["prod"]
          },
          "notes" => "Rolled out for the summer campaign hardware batch"
        }
      }
    })
  end
end

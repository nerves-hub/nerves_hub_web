defmodule NervesHubWeb.API.Schemas.DeploymentReleaseSchemas do
  alias NervesHubWeb.API.OpenAPI.SchemaHelpers
  alias NervesHubWeb.API.Schemas.DeploymentGroupSchemas
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule Author do
    OpenApiSpex.schema(%{
      description:
        "Who created the release: a user, or a product API key. Null for releases made before authors were recorded.",
      type: :object,
      nullable: true,
      properties: %{
        type: %Schema{type: :string, enum: ["user", "api_key"]},
        name: %Schema{type: :string},
        email: %Schema{type: :string, description: "Only for a user"}
      },
      required: [:type, :name],
      example: %{"type" => "user", "name" => "Jane Doe", "email" => "jane@example.com"}
    })
  end

  defmodule DeploymentRelease do
    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        number: %Schema{type: :integer, description: "The release's number within its deployment group, from 1"},
        firmware: DeploymentGroupSchemas.Firmware,
        archive_uuid: %Schema{type: :string, nullable: true},
        required: %Schema{
          type: :boolean,
          description: "Devices that have not reached a required release are updated to it before any newer release"
        },
        description: %Schema{type: :string, nullable: true},
        notes: %Schema{type: :string, nullable: true},
        connecting_code: %Schema{
          type: :string,
          nullable: true,
          description: "Elixir run on a device when it connects, as long as this release is the one it is sent"
        },
        connecting_code_mode: %Schema{
          type: :string,
          enum: ["first", "last", "override"],
          description:
            ~s{Where the release's connecting code runs relative to the deployment group's: "first" (before it), "last" (after it) or "override" (instead of it)}
        },
        delta_status: %Schema{
          type: :string,
          enum: ["ready", "preparing", "failed"],
          description:
            ~s{Whether the deltas this release's devices need are ready: "preparing" while one is still being built, "failed" if one gave up}
        },
        is_current: %Schema{type: :boolean, description: "Whether this is the deployment group's current release"},
        created_by: Author,
        inserted_at: SchemaHelpers.naive_timestamp("When it was created"),
        updated_at: SchemaHelpers.naive_timestamp("When it was last changed")
      },
      example: %{
        "number" => 3,
        "firmware" => %{
          "version" => "1.0.1",
          "architecture" => "arm",
          "platform" => "rpi0",
          "uuid" => "d9f8c63a-1234-5678-abcd-ef0123456789"
        },
        "archive_uuid" => nil,
        "required" => false,
        "description" => "Fixes the Wi-Fi reconnect loop",
        "notes" => "Roll out after the field test passes",
        "connecting_code" => nil,
        "connecting_code_mode" => "last",
        "delta_status" => "ready",
        "is_current" => true,
        "created_by" => %{"type" => "user", "name" => "Jane Doe", "email" => "jane@example.com"},
        "inserted_at" => "2024-01-01T00:00:00",
        "updated_at" => "2024-01-01T00:00:00"
      }
    })
  end

  defmodule DeploymentReleaseListResponse do
    OpenApiSpex.schema(%{
      description: "A deployment group's releases, newest first",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: DeploymentRelease}
      }
    })
  end

  defmodule DeploymentReleaseResponse do
    OpenApiSpex.schema(%{
      description: "A single release",
      type: :object,
      properties: %{
        data: DeploymentRelease
      }
    })
  end

  defmodule DeploymentReleaseCreationRequest do
    OpenApiSpex.schema(%{
      description: "POST body for creating a release, which becomes the deployment group's current release",
      type: :object,
      properties: %{
        firmware: %Schema{type: :string, description: "Firmware UUID"},
        archive: %Schema{
          type: :string,
          description: "Archive UUID. Left out, the release has no archive, whatever the previous release had."
        },
        required: %Schema{
          type: :boolean,
          description: "Devices that have not reached a required release are updated to it before any newer release",
          default: false
        },
        description: %Schema{type: :string, maxLength: 100},
        notes: %Schema{type: :string, maxLength: 1000},
        connecting_code: %Schema{
          type: :string,
          description: "Elixir run on a device when it connects, as long as this release is the one it is sent"
        },
        connecting_code_mode: %Schema{
          type: :string,
          enum: ["first", "last", "override"],
          description:
            ~s{Where the release's connecting code runs relative to the deployment group's: "first" (before it), "last" (after it) or "override" (instead of it)},
          default: "last"
        }
      },
      required: [:firmware],
      example: %{
        "firmware" => "d9f8c63a-1234-5678-abcd-ef0123456789",
        "required" => false,
        "description" => "Fixes the Wi-Fi reconnect loop"
      }
    })
  end

  defmodule DeploymentReleaseUpdateRequest do
    OpenApiSpex.schema(%{
      description:
        "PATCH body for changing a release. Only these fields can change once a release is made; any left out keep their value.",
      type: :object,
      properties: %{
        required: %Schema{
          type: :boolean,
          description: "Devices that have not reached a required release are updated to it before any newer release"
        },
        connecting_code: %Schema{
          type: :string,
          nullable: true,
          description:
            "Elixir run on a device when it connects, as long as this release is the one it is sent. Null or an empty string removes it."
        },
        connecting_code_mode: %Schema{
          type: :string,
          enum: ["first", "last", "override"],
          description:
            ~s{Where the release's connecting code runs relative to the deployment group's: "first" (before it), "last" (after it) or "override" (instead of it)}
        }
      },
      example: %{
        "required" => true,
        "connecting_code" => "Logger.info(\"connected\")",
        "connecting_code_mode" => "first"
      }
    })
  end
end

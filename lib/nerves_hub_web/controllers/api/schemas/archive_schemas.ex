defmodule NervesHubWeb.API.Schemas.ArchiveSchemas do
  alias NervesHubWeb.API.Schemas.ErrorSchemas.ChangesetErrorResponse
  alias NervesHubWeb.API.Schemas.ErrorSchemas.ErrorResponse
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule Archive do
    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        uuid: %Schema{type: :string, format: :uuid},
        version: %Schema{type: :string},
        platform: %Schema{type: :string},
        architecture: %Schema{type: :string},
        author: %Schema{type: :string, nullable: true},
        description: %Schema{type: :string, nullable: true},
        misc: %Schema{type: :string, nullable: true},
        vcs_identifier: %Schema{type: :string, nullable: true},
        size: %Schema{type: :integer, description: "Size in bytes"},
        inserted_at: %Schema{type: :string, format: :"date-time"}
      },
      example: %{
        "uuid" => "d9f8c63a-1234-5678-abcd-ef0123456789",
        "version" => "1.0.0",
        "platform" => "rpi0",
        "architecture" => "arm",
        "author" => "NervesHub",
        "description" => "Supporting files",
        "misc" => nil,
        "vcs_identifier" => "a1b2c3d",
        "size" => 1_048_576,
        "inserted_at" => "2026-01-15T09:34:27"
      }
    })
  end

  defmodule ArchiveResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for a single Archive",
      type: :object,
      properties: %{
        data: Archive
      },
      example: %{
        "data" => %{
          "uuid" => "d9f8c63a-1234-5678-abcd-ef0123456789",
          "version" => "1.0.0",
          "platform" => "rpi0",
          "architecture" => "arm",
          "author" => "NervesHub",
          "description" => "Supporting files",
          "misc" => nil,
          "vcs_identifier" => "a1b2c3d",
          "size" => 1_048_576,
          "inserted_at" => "2026-01-15T09:34:27"
        }
      }
    })
  end

  defmodule ArchiveUploadErrorResponse do
    OpenApiSpex.schema(%{
      description: """
      Upload failure.

      Changeset failures (a duplicate UUID, a version that is not SemVer) are
      keyed by field. A signature failure carries a single `detail` message
      instead.
      """,
      type: :object,
      oneOf: [
        ChangesetErrorResponse,
        ErrorResponse
      ],
      example: %{
        "errors" => %{
          "detail" => "The signature does not match any of this organization's signing keys, or the file is corrupt."
        }
      }
    })
  end

  defmodule ArchiveListResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for multiple Archives",
      type: :object,
      properties: %{
        data: %Schema{
          description: "The Archive details",
          type: :array,
          items: Archive
        }
      },
      example: %{
        "data" => [
          %{
            "uuid" => "d9f8c63a-1234-5678-abcd-ef0123456789",
            "version" => "1.0.0",
            "platform" => "rpi0",
            "architecture" => "arm",
            "author" => "NervesHub",
            "description" => "Supporting files",
            "misc" => nil,
            "vcs_identifier" => "a1b2c3d",
            "size" => 1_048_576,
            "inserted_at" => "2026-01-15T09:34:27"
          }
        ]
      }
    })
  end
end

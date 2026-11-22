defmodule NervesHubWeb.API.Schemas.SupportScriptSchemas do
  alias NervesHubWeb.API.OpenAPI.SchemaHelpers
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule SupportScript do
    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        name: %Schema{type: :string},
        text: %Schema{type: :string},
        language: %Schema{type: :string, enum: ["elixir", "shell"], default: "elixir"},
        tags: %Schema{type: :array, items: %Schema{type: :string}, nullable: true},
        inserted_at: SchemaHelpers.naive_timestamp("When it was created"),
        updated_at: SchemaHelpers.naive_timestamp("When it was last changed"),
        created_by: %Schema{
          type: :object,
          description:
            "The user who created the script. Left out when no user did, as for a script a product API key created.",
          properties: %{
            id: %Schema{type: :integer},
            name: %Schema{type: :string},
            email: %Schema{type: :string}
          }
        }
      },
      example: %{
        "id" => 1,
        "name" => "Clean Disk",
        "text" => "Clean.disk()",
        "language" => "elixir",
        "tags" => ["cleanup"],
        "inserted_at" => "2026-03-28T08:10:20",
        "updated_at" => "2026-06-23T08:10:20",
        "created_by" => %{
          "id" => 1,
          "name" => "Waffles t'Doggo",
          "email" => "waffles@doggo.com"
        }
      }
    })
  end

  defmodule SupportScriptMinimal do
    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        name: %Schema{type: :string},
        language: %Schema{type: :string, enum: ["elixir", "shell"], default: "elixir"},
        tags: %Schema{type: :array, items: %Schema{type: :string}, nullable: true}
      },
      example: %{
        "id" => 1,
        "name" => "Clean Disk",
        "language" => "elixir",
        "tags" => ["cleanup"]
      }
    })
  end

  defmodule SupportScriptIndexResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for multiple Support Scripts",
      type: :object,
      properties: %{
        data: %Schema{description: "The Support Script details", type: :array, items: SupportScriptMinimal},
        pagination: %Schema{
          type: :object,
          properties: %{
            page_number: %Schema{type: :integer},
            page_size: %Schema{type: :integer},
            total_pages: %Schema{type: :integer},
            total_entries: %Schema{type: :integer}
          }
        }
      },
      example: %{
        "data" => [
          %{
            "id" => 1,
            "name" => "Clean Disk",
            "language" => "elixir",
            "tags" => ["cleanup"]
          },
          %{
            "id" => 2,
            "name" => "Dim the lights",
            "language" => "shell",
            "tags" => ["lights"]
          }
        ],
        "pagination" => %{
          "page_size" => 20,
          "total_pages" => 1,
          "page_number" => 1,
          "total_entries" => 2
        }
      }
    })
  end

  defmodule SupportScriptShowResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for a single Support Script",
      type: :object,
      properties: %{
        data: SupportScript
      },
      example: %{
        "data" => %{
          "id" => 1,
          "name" => "Snoot Boop",
          "text" => "Snoot.boop()",
          "language" => "elixir",
          "tags" => ["snoots"],
          "inserted_at" => "2026-03-28T08:10:20",
          "updated_at" => "2026-06-23T08:10:20",
          "created_by" => %{
            "id" => 1,
            "name" => "Waffles t'Doggo",
            "email" => "waffles@doggo.com"
          }
        }
      }
    })
  end

  defmodule SupportScriptCreationRequest do
    OpenApiSpex.schema(%{
      description: "POST body for adding a Support Script to a Product",
      type: :object,
      properties: %{
        name: %Schema{type: :string},
        text: %Schema{type: :string},
        language: %Schema{
          type: :string,
          enum: ["elixir", "shell"],
          default: "elixir",
          description: "How the device should interpret `text`. Defaults to Elixir."
        },
        tags: SchemaHelpers.request_tags()
      },
      required: [:name, :text],
      example: %{
        "name" => "Clean Disk",
        "text" => "Disk.clean()",
        "language" => "elixir",
        "tags" => ["cleanup"]
      }
    })
  end

  defmodule SupportScriptUpdateRequest do
    OpenApiSpex.schema(%{
      description: "PUT body for updating a Support Script",
      type: :object,
      properties: %{
        name: %Schema{type: :string},
        text: %Schema{type: :string},
        language: %Schema{
          type: :string,
          enum: ["elixir", "shell"],
          default: "elixir",
          description: "How the device should interpret `text`. Defaults to Elixir."
        },
        tags: SchemaHelpers.request_tags()
      },
      example: %{
        "name" => "Clean Disk",
        "text" => "Disk.clean()",
        "language" => "elixir",
        "tags" => ["cleanup"]
      }
    })
  end
end

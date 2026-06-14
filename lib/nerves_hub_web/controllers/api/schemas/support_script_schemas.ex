defmodule NervesHubWeb.API.Schemas.SupportScriptSchemas do
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule SupportScript do
    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        id: %Schema{type: :string},
        name: %Schema{type: :string},
        text: %Schema{type: :string},
        tags: %Schema{type: :string},
        inserted_at: %Schema{type: :string, format: "date-time"},
        updated_at: %Schema{type: :string, format: "date-time"},
        created_by: %Schema{
          type: :object,
          properties: %{
            id: %Schema{type: :string},
            name: %Schema{type: :string},
            email: %Schema{type: :string}
          }
        }
      },
      example: %{
        "id" => "1",
        "name" => "Clean Disk",
        "text" => "Clean.disk()",
        "tags" => "cleanup",
        "inserted_at" => "2026-03-28T08:10:20Z",
        "updated_at" => "2026-06-23T08:10:20Z",
        "created_by" => %{
          "id" => "1",
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
        id: %Schema{type: :string},
        name: %Schema{type: :string},
        tags: %Schema{type: :string}
      },
      example: %{
        "id" => "1",
        "name" => "Clean Disk",
        "tags" => "cleanup"
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
            "id" => "1",
            "name" => "Clean Disk",
            "tags" => "cleanup"
          },
          %{
            "id" => "2",
            "name" => "Dim the lights",
            "tags" => "lights"
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
          "id" => "1",
          "name" => "Snoot Boop",
          "text" => "Snoot.boop()",
          "tags" => "snoots",
          "inserted_at" => "2026-03-28T08:10:20Z",
          "updated_at" => "2026-06-23T08:10:20Z",
          "created_by" => %{
            "id" => "1",
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
        tags: %Schema{type: :string}
      },
      required: [:name, :text],
      example: %{
        "name" => "Clean Disk",
        "text" => "Disk.clean()",
        "tags" => "cleanup"
      }
    })
  end

  defmodule SupportScriptUpdateRequest do
    OpenApiSpex.schema(%{
      description: "POST body for updating a Support Script",
      type: :object,
      properties: %{
        name: %Schema{type: :string},
        text: %Schema{type: :string},
        tags: %Schema{type: :string}
      },
      example: %{
        "name" => "Clean Disk",
        "text" => "Disk.clean()",
        "tags" => "cleanup"
      }
    })
  end
end

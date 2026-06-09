defmodule NervesHubWeb.API.Schemas.KeySchemas do
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule SigningKey do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        name: %Schema{type: :string},
        key: %Schema{type: :string}
      },
      example: %{
        "data" => %{
          "name" => "CI",
          "key" => "abc123="
        }
      }
    })
  end

  defmodule SigningKeyIndexResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for multiple Signing Keys",
      type: :object,
      properties: %{
        data: %Schema{description: "The Signing Key details", type: :array, items: SigningKey}
      },
      example: %{
        "data" => [
          %{
            "name" => "QA",
            "key" => "abc123="
          },
          %{
            "name" => "CI",
            "key" => "doerayme="
          }
        ]
      }
    })
  end

  defmodule SigningKeyShowResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for a single Signing Key",
      type: :object,
      properties: %{
        data: SigningKey
      },
      example: %{
        "data" => %{
          "name" => "QA",
          "key" => "abc123="
        }
      }
    })
  end

  defmodule SigningKeyCreationRequest do
    OpenApiSpex.schema(%{
      description: "POST body for adding a Signing Key to an Organization",
      type: :object,
      properties: %{
        name: %Schema{type: :string},
        key: %Schema{type: :string}
      },
      required: [:name, :key],
      example: %{
        "name" => "QA",
        "key" => "abc123="
      }
    })
  end
end

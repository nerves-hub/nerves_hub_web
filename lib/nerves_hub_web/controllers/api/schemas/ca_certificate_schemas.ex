defmodule NervesHubWeb.API.Schemas.CACertificateSchemas do
  alias OpenApiSpex.Schema
  require OpenApiSpex

  defmodule CACertificate do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      example: %{
        "description" => "Example CA",
        "jitp" => %{
          "description" => "Production",
          "product_name" => "ExampleProduct",
          "tags" => ["prod"]
        },
        "not_after" => "2050-04-20T00:33:09Z",
        "not_before" => "2025-04-20T00:28:09Z",
        "serial" => "4016688295714810857"
      },
      properties: %{
        description: %Schema{
          pattern: ~r/[a-zA-Z][a-zA-Z0-9_]+/,
          type: :string
        },
        inserted_at: %Schema{
          description: "Creation timestamp",
          format: :"date-time",
          type: :string
        },
        jitp: %Schema{
          properties: %{
            description: %Schema{
              type: :string
            },
            product_name: %Schema{
              type: :string
            },
            tags: %Schema{
              type: :string
            }
          },
          type: :object
        },
        not_after: %Schema{
          description: "Certificate expiration timestamp",
          format: :"date-time",
          type: :string
        },
        not_before: %Schema{
          description: "Certificate valid from timestamp",
          format: :"date-time",
          type: :string
        },
        serial: %Schema{type: :integer},
        updated_at: %Schema{
          description: "Last updated timestamp",
          format: :"date-time",
          type: :string
        }
      },
      type: :object
    })
  end

  defmodule CACertificateListResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for multiple CA Certificates",
      example: %{
        "data" => [
          %{
            "description" => "Example CA",
            "jitp" => %{
              "description" => "Staging",
              "product_name" => "StagingProduct",
              "tags" => ["staging"]
            },
            "not_after" => "2050-04-20T00:33:09Z",
            "not_before" => "2025-04-20T00:28:09Z",
            "serial" => "4016688295714810857"
          },
          %{
            "description" => "Another Example CA",
            "jitp" => %{
              "description" => "QA",
              "product_name" => "QAProduct",
              "tags" => ["qa"]
            },
            "not_after" => "2050-04-20T00:33:09Z",
            "not_before" => "2025-04-20T00:28:09Z",
            "serial" => "8033376591429621714"
          }
        ]
      },
      properties: %{
        data: %Schema{
          description: "The CA Certificate details",
          items: CACertificate,
          type: :array
        }
      },
      type: :object
    })
  end

  defmodule CACertificateCreationRequest do
    OpenApiSpex.schema(%{
      description: "POST body for creating a CA Certificate",
      example: %{
        "product" => %{
          "cert" => "base64 encoded certificate",
          "description" => "Example CA",
          "jitp" => %{
            "description" => "Production",
            "product_id" => 33_438,
            "tags" => ["prod"]
          }
        }
      },
      properties: %{
        ca_certificate: %Schema{
          properties: %{
            cert: %Schema{type: :string},
            description: %Schema{type: :string},
            jitp: %Schema{
              properties: %{
                description: %Schema{type: :string},
                product_id: %Schema{type: :integer},
                tags: %Schema{items: %Schema{type: :string}, type: :array}
              },
              type: :object
            }
          }
        }
      },
      required: [:description, :cert],
      type: :object
    })
  end
end

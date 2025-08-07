defmodule NervesHubWeb.API.Schemas.CACertificateSchemas do
  alias OpenApiSpex.Schema
  require OpenApiSpex

  defmodule CACertificate do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        serial: %Schema{type: :integer},
        description: %Schema{
          type: :string,
          pattern: ~r/[a-zA-Z][a-zA-Z0-9_]+/
        },
        jitp: %Schema{
          type: :object,
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
          }
        },
        not_after: %Schema{
          type: :string,
          description: "Certificate expiration timestamp",
          format: :"date-time"
        },
        not_before: %Schema{
          type: :string,
          description: "Certificate valid from timestamp",
          format: :"date-time"
        },
        inserted_at: %Schema{
          type: :string,
          description: "Creation timestamp",
          format: :"date-time"
        },
        updated_at: %Schema{
          type: :string,
          description: "Last updated timestamp",
          format: :"date-time"
        }
      },
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
      }
    })
  end

  defmodule CACertificateListResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for multiple CA Certificates",
      type: :object,
      properties: %{
        data: %Schema{
          description: "The CA Certificate details",
          type: :array,
          items: CACertificate
        }
      },
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
      }
    })
  end

  defmodule CACertificateCreationRequest do
    OpenApiSpex.schema(%{
      description: "POST body for creating a CA Certificate",
      type: :object,
      properties: %{
        ca_certificate: %Schema{
          properties: %{
            description: %Schema{type: :string},
            cert: %Schema{type: :string},
            jitp: %Schema{
              type: :object,
              properties: %{
                description: %Schema{type: :string},
                product_id: %Schema{type: :integer},
                tags: %Schema{type: :array, items: %Schema{type: :string}}
              }
            }
          }
        }
      },
      required: [:description, :cert],
      example: %{
        "product" => %{
          "description" => "Example CA",
          "cert" => "base64 encoded certificate",
          "jitp" => %{
            "description" => "Production",
            "tags" => ["prod"],
            "product_id" => 33_438
          }
        }
      }
    })
  end
end

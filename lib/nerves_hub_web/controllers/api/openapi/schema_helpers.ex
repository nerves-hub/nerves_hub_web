defmodule NervesHubWeb.API.OpenAPI.SchemaHelpers do
  import OpenApiSpex.Operation, only: [response: 3]

  alias NervesHubWeb.API.Schemas.ErrorSchemas

  def auth_error_responses() do
    [
      unauthorized: {"Unauthorized", "application/json", ErrorSchemas.ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorSchemas.ErrorResponse}
    ]
  end

  def common_errors() do
    %{
      401 => response("Unauthorized", "application/json", ErrorSchemas.ErrorResponse),
      403 => response("Forbidden", "application/json", ErrorSchemas.ErrorResponse)
    }
  end

  def not_found_error() do
    %{404 => response("Not Found", "application/json", ErrorSchemas.ErrorResponse)}
  end

  def validation_error() do
    %{422 => response("Unprocessable Entity", "application/json", ErrorSchemas.ChangesetErrorResponse)}
  end

  def org_param() do
    %OpenApiSpex.Parameter{
      name: :org_name,
      in: :path,
      description: "Organization Name",
      required: true,
      schema: %OpenApiSpex.Schema{type: :string},
      example: "example_org"
    }
  end

  def product_param() do
    %OpenApiSpex.Parameter{
      name: :product_name,
      in: :path,
      description: "Product Name",
      required: true,
      schema: %OpenApiSpex.Schema{type: :string},
      example: "example_product"
    }
  end

  def device_param() do
    %OpenApiSpex.Parameter{
      name: :identifier,
      in: :path,
      description: "Device Identifier",
      required: true,
      schema: %OpenApiSpex.Schema{type: :string},
      example: "abc123"
    }
  end

  def pagination_param() do
    %OpenApiSpex.Parameter{
      name: :pagination,
      description: "Pagination",
      in: :query,
      required: false,
      style: :deepObject,
      schema: %OpenApiSpex.Schema{
        type: :object,
        properties: %{
          page: %OpenApiSpex.Schema{type: :integer, default: 1, example: "5"},
          page_size: %OpenApiSpex.Schema{type: :integer, default: 10, example: "20"}
        }
      }
    }
  end
end

defmodule NervesHubWeb.API.OpenAPI.SchemaHelpers do
  import OpenApiSpex.Operation, only: [response: 3]

  alias NervesHubWeb.API.Schemas.ErrorSchemas

  @doc """
  A record's `inserted_at` or `updated_at`.

  Ecto's `timestamps()` are naive, so the API writes them in UTC as ISO 8601
  with no offset, such as `2026-01-15T09:34:27`. RFC 3339's `date-time` needs
  an offset, so this gives no format: a client parsing `date-time` strictly
  would reject every one of them.
  """
  def naive_timestamp(description) do
    %OpenApiSpex.Schema{
      type: :string,
      description:
        "#{description}, in UTC. Written without an offset, such as `2026-01-15T09:34:27`, so not an RFC 3339 `date-time`."
    }
  end

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

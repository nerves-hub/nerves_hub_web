defmodule NervesHubWeb.API.OpenAPI.DeviceLogControllerSpecs do
  @moduledoc """
  OpenAPI operations for `NervesHubWeb.API.DeviceLogController`.

  Device logs are served from two URLs — the product-scoped one and the short
  device one — and only the first carries org and product path parameters, so
  the two are described here rather than with a single `operation/2` in the
  controller.
  """

  import OpenApiSpex.Operation, only: [response: 3]

  alias NervesHubWeb.API.OpenAPI.SchemaHelpers
  alias NervesHubWeb.API.Schemas.DeviceLogSchemas
  alias NervesHubWeb.API.Schemas.ErrorSchemas

  @organization_parameter SchemaHelpers.org_param()
  @product_parameter SchemaHelpers.product_param()
  @device_parameter SchemaHelpers.device_param()

  @level_parameter %OpenApiSpex.Parameter{
    name: :level,
    in: :query,
    description:
      "Only lines logged at these levels. Comma separated for more than one. Matched as given — a level no device has logged at matches nothing",
    required: false,
    schema: %OpenApiSpex.Schema{type: :string},
    example: "error,warning"
  }

  @since_parameter %OpenApiSpex.Parameter{
    name: :since,
    in: :query,
    description: "Only lines logged at or after this ISO 8601 timestamp",
    required: false,
    schema: %OpenApiSpex.Schema{type: :string, format: :"date-time"},
    example: "2026-08-16T09:00:00Z"
  }

  @before_parameter %OpenApiSpex.Parameter{
    name: :before,
    in: :query,
    description:
      "Only lines logged strictly before this ISO 8601 timestamp. To page back through history, pass the timestamp of the oldest line you received",
    required: false,
    schema: %OpenApiSpex.Schema{type: :string, format: :"date-time"},
    example: "2026-08-16T09:14:00.123456Z"
  }

  @limit_parameter %OpenApiSpex.Parameter{
    name: :limit,
    in: :query,
    description: "How many lines to return, from 1 to 1000",
    required: false,
    schema: %OpenApiSpex.Schema{type: :integer, default: 100},
    example: "250"
  }

  @order_parameter %OpenApiSpex.Parameter{
    name: :order,
    in: :query,
    description: "`desc` for newest first, `asc` for oldest first",
    required: false,
    schema: %OpenApiSpex.Schema{type: :string, enum: ["desc", "asc"], default: "desc"},
    example: "asc"
  }

  @query_parameters [
    @level_parameter,
    @since_parameter,
    @before_parameter,
    @limit_parameter,
    @order_parameter
  ]

  @path_structures %{
    short: %{
      path: "/api/devices/{identifier}/logs",
      tags: ["Devices (short URL)"],
      parameters: [@device_parameter]
    },
    long: %{
      path: "/api/orgs/{org_name}/products/{product_name}/devices/{identifier}/logs",
      tags: ["Device Logs"],
      parameters: [@organization_parameter, @product_parameter, @device_parameter]
    }
  }

  @common_errors SchemaHelpers.common_errors()
  @not_found_error SchemaHelpers.not_found_error()

  @index_responses %{
    200 => response("Device Log List Response", "application/json", DeviceLogSchemas.DeviceLogListResponse),
    422 => response("Unusable query parameter", "application/json", ErrorSchemas.ErrorResponse),
    501 =>
      response(
        "This platform has no analytics database, so no logs are stored",
        "application/json",
        ErrorSchemas.ErrorResponse
      )
  }

  def add_operations(openapi) do
    openapi
    |> index_action(:long)
    |> index_action(:short)
  end

  defp index_action(openapi, path_structure) do
    opts = @path_structures[path_structure]

    list_operation = %OpenApiSpex.Operation{
      tags: opts.tags,
      summary: "List the Log Lines a Device has sent",
      description: """
      The log lines this device sent over the logging extension, newest first.

      Lines stay readable after the extension is turned off for the product or
      the device — the setting governs what arrives, not what can be read. They
      are not kept forever, though: log lines are dropped three days after they
      were logged.

      To page back through history, ask for a `limit` and then pass the
      `timestamp` of the oldest line you received as the next request's
      `before`.
      """,
      operationId: "NervesHubWeb.API.DeviceLogController.index.#{path_structure}",
      parameters: opts.parameters ++ @query_parameters,
      responses: @index_responses |> Map.merge(@common_errors) |> Map.merge(@not_found_error),
      callbacks: %{},
      security: [%{"bearer_auth" => []}],
      extensions: %{}
    }

    updated_paths = Map.put(openapi.paths, opts.path, %OpenApiSpex.PathItem{get: list_operation})

    Map.put(openapi, :paths, updated_paths)
  end
end

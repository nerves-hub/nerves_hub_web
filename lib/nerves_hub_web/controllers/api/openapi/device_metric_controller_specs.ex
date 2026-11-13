defmodule NervesHubWeb.API.OpenAPI.DeviceMetricControllerSpecs do
  @moduledoc """
  OpenAPI operations for `NervesHubWeb.API.DeviceMetricController`.

  Device metrics are served from two URLs — the product-scoped one and the
  short device one — and only the first carries org and product path
  parameters, so the two are described here rather than with a single
  `operation/2` in the controller.
  """

  import OpenApiSpex.Operation, only: [response: 3]

  alias NervesHubWeb.API.OpenAPI.SchemaHelpers
  alias NervesHubWeb.API.Schemas.DeviceMetricSchemas
  alias NervesHubWeb.API.Schemas.ErrorSchemas

  @organization_parameter SchemaHelpers.org_param()
  @product_parameter SchemaHelpers.product_param()
  @device_parameter SchemaHelpers.device_param()

  @key_parameter %OpenApiSpex.Parameter{
    name: :key,
    in: :query,
    description:
      "Only these metrics. Comma separated for more than one. Matched as given — a name the device has never reported matches nothing, and a report that carried none of them is left out",
    required: false,
    schema: %OpenApiSpex.Schema{type: :string},
    example: "cpu_temp,mem_used_percent"
  }

  @since_parameter %OpenApiSpex.Parameter{
    name: :since,
    in: :query,
    description:
      "Only reports taken at or after this ISO 8601 timestamp. Inclusive, so a client following a device forward from its newest report gets that report again",
    required: false,
    schema: %OpenApiSpex.Schema{type: :string, format: :"date-time"},
    example: "2026-08-16T09:00:00Z"
  }

  @before_parameter %OpenApiSpex.Parameter{
    name: :before,
    in: :query,
    description:
      "Only reports taken strictly before this ISO 8601 timestamp. To page back through history, pass the timestamp of the oldest report you received",
    required: false,
    schema: %OpenApiSpex.Schema{type: :string, format: :"date-time"},
    example: "2026-08-16T09:14:00.123456Z"
  }

  @limit_parameter %OpenApiSpex.Parameter{
    name: :limit,
    in: :query,
    description: "How many reports to return, from 1 to 1000. Counts reports, not readings",
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
    @key_parameter,
    @since_parameter,
    @before_parameter,
    @limit_parameter,
    @order_parameter
  ]

  @path_structures %{
    short: %{
      path: "/api/devices/{identifier}/metrics",
      tags: ["Devices (short URL)"],
      parameters: [@device_parameter]
    },
    long: %{
      path: "/api/orgs/{org_name}/products/{product_name}/devices/{identifier}/metrics",
      tags: ["Device Metrics"],
      parameters: [@organization_parameter, @product_parameter, @device_parameter]
    }
  }

  @common_errors SchemaHelpers.common_errors()
  @not_found_error SchemaHelpers.not_found_error()

  @index_responses %{
    200 =>
      response(
        "Device Metric Report List Response",
        "application/json",
        DeviceMetricSchemas.DeviceMetricReportListResponse
      ),
    422 => response("Unusable query parameter", "application/json", ErrorSchemas.ErrorResponse),
    501 =>
      response(
        "This platform has no analytics database, so no metric history is stored",
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
      summary: "List the Metric Reports a Device has sent",
      description: """
      The metrics this device reported, over the `health` or `metrics`
      extension, as reports: each one a timestamp and the readings the device
      took at it, newest first.

      History is kept for thirty days. A report keeps only the readings that
      were stored: names longer than 64 bytes, values that were not numbers,
      and names past the per-report cap were dropped on the way in.

      To page back through history, ask for a `limit` and then pass the
      `timestamp` of the oldest report you received as the next request's
      `before`. A page never ends partway through a report.
      """,
      operationId: "NervesHubWeb.API.DeviceMetricController.index.#{path_structure}",
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

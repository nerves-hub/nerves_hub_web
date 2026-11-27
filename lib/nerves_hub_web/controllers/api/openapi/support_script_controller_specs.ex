defmodule NervesHubWeb.API.OpenAPI.SupportScriptControllerSpecs do
  import OpenApiSpex.Operation, only: [response: 3]

  alias NervesHubWeb.API.OpenAPI.SchemaHelpers
  alias NervesHubWeb.API.Schemas.SupportScriptSchemas

  @organization_parameter SchemaHelpers.org_param()
  @product_parameter SchemaHelpers.product_param()
  @device_parameter SchemaHelpers.device_param()
  @pagination_parameter SchemaHelpers.pagination_param(25)
  @query_param_error SchemaHelpers.query_param_error()

  # The filters `ScriptFiltering.filter/4` applies.
  @filters_parameter %OpenApiSpex.Parameter{
    name: :filters,
    description:
      "Filtering. Each filter given narrows the list. " <>
        "A key that isn't a filter, or a value its filter can't take, is refused with a 422. " <>
        "An empty value leaves its filter unset.",
    in: :query,
    style: :deepObject,
    required: false,
    schema: %OpenApiSpex.Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        name: %OpenApiSpex.Schema{
          type: :string,
          description: "Scripts whose name contains this.",
          example: "reset"
        },
        search: %OpenApiSpex.Schema{
          type: :string,
          description: "Scripts whose name or tags contain this.",
          example: "network"
        },
        tags: %OpenApiSpex.Schema{
          type: :string,
          description:
            "Tags, comma-separated: scripts with every one of them. A tag can't contain a space, " <>
              "and matches any of a script's tags containing it.",
          example: "diagnostics"
        }
      }
    }
  }

  @path_structures %{
    short: %{
      path_prefix: "/api/devices/{identifier}/scripts",
      tags: ["Devices (short URL)"],
      parameters: [@device_parameter]
    },
    long: %{
      path_prefix: "/api/orgs/{org_name}/products/{product_name}/scripts",
      tags: ["Support Scripts"],
      parameters: [
        @organization_parameter,
        @product_parameter
      ]
    }
  }

  def add_operations(openapi) do
    openapi
    |> index_action(:long)
    |> index_action(:short)
  end

  defp index_action(openapi, path_structure) do
    opts = @path_structures[path_structure]

    operation_id =
      case path_structure do
        :long -> "NervesHubWeb.API.ScriptController.index"
        :short -> "NervesHubWeb.API.DevicesController.scripts"
      end

    list_operation =
      support_script_operation(
        "List Support Scripts",
        operation_id,
        opts.parameters ++ [@pagination_parameter, @filters_parameter],
        opts.tags,
        response:
          Map.put(
            @query_param_error,
            200,
            response(
              "Support Scripts List Response",
              "application/json",
              SupportScriptSchemas.SupportScriptIndexResponse
            )
          )
      )

    add_to_paths(openapi, opts.path_prefix, :get, list_operation)
  end

  @common_errors SchemaHelpers.common_errors()

  defp support_script_operation(summary, operation_id, parameters, tags, opts) do
    %OpenApiSpex.Operation{
      tags: tags,
      summary: summary,
      operationId: operation_id,
      parameters: parameters,
      requestBody: opts[:request_body],
      responses: Map.merge(@common_errors, opts[:response] || %{}),
      callbacks: %{},
      security: [%{"bearer_auth" => []}],
      extensions: %{}
    }
  end

  defp add_to_paths(openapi, path, method, operation) do
    updated_path = Map.put(openapi.paths[path], method, operation)
    updated_paths = Map.put(openapi.paths, path, updated_path)

    Map.put(openapi, :paths, updated_paths)
  end
end

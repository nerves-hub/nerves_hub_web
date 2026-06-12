defmodule NervesHubWeb.API.OpenAPI.SupportScriptControllerSpecs do
  import OpenApiSpex.Operation, only: [response: 3]

  alias NervesHubWeb.API.OpenAPI.SchemaHelpers
  alias NervesHubWeb.API.Schemas.SupportScriptSchemas

  @organization_parameter SchemaHelpers.org_param()
  @product_parameter SchemaHelpers.product_param()
  @device_parameter SchemaHelpers.device_param()
  @pagination_parameter SchemaHelpers.pagination_param()

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
        opts.parameters ++ [@pagination_parameter],
        opts.tags,
        response: %{
          200 =>
            response(
              "Support Scripts List Response",
              "application/json",
              SupportScriptSchemas.SupportScriptIndexResponse
            )
        }
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

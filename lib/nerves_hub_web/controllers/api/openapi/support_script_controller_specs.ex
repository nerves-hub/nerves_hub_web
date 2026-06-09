defmodule NervesHubWeb.API.OpenAPI.SupportScriptControllerSpecs do
  import OpenApiSpex.Operation, only: [response: 3]

  alias NervesHubWeb.API.Schemas.SupportScriptSchemas

  @organization_parameter %OpenApiSpex.Parameter{
    name: :org_name,
    in: :path,
    description: "Organization Name",
    required: true,
    schema: %OpenApiSpex.Schema{type: :string},
    example: "example_org"
  }

  @product_parameter %OpenApiSpex.Parameter{
    name: :product_name,
    in: :path,
    description: "Product Name",
    required: true,
    schema: %OpenApiSpex.Schema{type: :string},
    example: "example_product"
  }

  @device_parameter %OpenApiSpex.Parameter{
    name: :identifier,
    in: :path,
    description: "Device Identifier",
    required: true,
    schema: %OpenApiSpex.Schema{type: :string},
    example: "abc123"
  }

  @pagination_parameter %OpenApiSpex.Parameter{
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

  defp support_script_operation(summary, operation_id, parameters, tags, opts) do
    %OpenApiSpex.Operation{
      tags: tags,
      summary: summary,
      operationId: operation_id,
      parameters: parameters,
      requestBody: opts[:request_body],
      responses: opts[:response],
      callbacks: %{},
      security: [%{}, %{"bearer_auth" => []}],
      extensions: %{}
    }
  end

  defp add_to_paths(openapi, path, method, operation) do
    updated_path = Map.put(openapi.paths[path], method, operation)
    updated_paths = Map.put(openapi.paths, path, updated_path)

    Map.put(openapi, :paths, updated_paths)
  end
end

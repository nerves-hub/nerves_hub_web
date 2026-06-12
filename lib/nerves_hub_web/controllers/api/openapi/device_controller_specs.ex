defmodule NervesHubWeb.API.OpenAPI.DeviceControllerSpecs do
  import OpenApiSpex.Operation, only: [request_body: 4, response: 3]

  alias NervesHubWeb.API.OpenAPI.SchemaHelpers
  alias NervesHubWeb.API.Schemas.DeviceCertificateSchemas
  alias NervesHubWeb.API.Schemas.DeviceSchemas

  @organization_parameter SchemaHelpers.org_param()
  @product_parameter SchemaHelpers.product_param()
  @device_parameter SchemaHelpers.device_param()
  @pagination_parameter SchemaHelpers.pagination_param()

  @sort_by_parameter %OpenApiSpex.Parameter{
    name: :sort,
    description: "Sort By",
    in: :query,
    required: false,
    schema: %OpenApiSpex.Schema{type: :string},
    example: "identifier"
  }

  @sort_direction_parameter %OpenApiSpex.Parameter{
    name: :sort_direction,
    description: "Sort Direction",
    in: :query,
    required: false,
    schema: %OpenApiSpex.Schema{type: :string},
    example: "asc"
  }

  @filters_parameter %OpenApiSpex.Parameter{
    name: :filters,
    description: "Filtering",
    in: :query,
    style: :deepObject,
    required: false,
    schema: %OpenApiSpex.Schema{
      type: :object,
      properties: %{
        alarm: %OpenApiSpex.Schema{type: :string, required: false, example: "SomeAlarm"},
        alarm_status: %OpenApiSpex.Schema{type: :string, required: false, enum: ["with", "without"]},
        connection: %OpenApiSpex.Schema{type: :string, required: false, enum: ["connected", "disconnected", "not_seen"]},
        deployment_id: %OpenApiSpex.Schema{type: :string, required: false, example: "12"},
        display_deleted: %OpenApiSpex.Schema{type: :string, required: false, enum: ["include", "exclude", "only"]},
        firmware_version: %OpenApiSpex.Schema{type: :string, required: false, example: "1.10.0"},
        has_no_tags: %OpenApiSpex.Schema{type: :string, required: false, enum: ["true", "false"]},
        health_status: %OpenApiSpex.Schema{
          type: :string,
          required: false,
          enum: ["healthy", "unhealthy", "warning", "unknown"]
        },
        identifier: %OpenApiSpex.Schema{type: :string, required: false, example: "sn123"},
        only_updating: %OpenApiSpex.Schema{type: :string, required: false, enum: ["true", "false"]},
        platform: %OpenApiSpex.Schema{type: :string, required: false, example: "rpi4"},
        search: %OpenApiSpex.Schema{type: :string, required: false, example: "sn123"},
        tags: %OpenApiSpex.Schema{type: :string, required: false, example: "prod,staging"},
        updates: %OpenApiSpex.Schema{type: :string, required: false, enum: ["enabled", "disabled", "penalty-box"]}
      }
    }
  }

  @device_response %{
    200 => response("Device Response", "application/json", DeviceSchemas.DeviceResponse)
  }

  @device_creation_response %{
    201 => response("Device Response", "application/json", DeviceSchemas.DeviceResponse)
  }

  @device_list_response %{
    200 => response("Device List Response", "application/json", DeviceSchemas.DeviceListResponse)
  }

  @no_content_response %{
    204 => %OpenApiSpex.Response{description: "No content"}
  }

  @common_errors SchemaHelpers.common_errors()
  @not_found_error SchemaHelpers.not_found_error()
  @validation_error SchemaHelpers.validation_error()

  @path_structures %{
    short: %{
      path_prefix: "/api/devices/{identifier}",
      tags: ["Devices (short URL)"],
      parameters: [@device_parameter]
    },
    long: %{
      path_prefix: "/api/orgs/{org_name}/products/{product_name}/devices/{identifier}",
      tags: ["Devices"],
      parameters: [
        @organization_parameter,
        @product_parameter,
        @device_parameter
      ]
    }
  }

  def add_operations(openapi) do
    openapi
    # short urls
    |> general_actions(:short)
    |> code_action(:short)
    |> move_action(:short)
    |> reboot_action(:short)
    |> reconnect_action(:short)
    |> upgrade_action(:short)
    |> penalty_action(:short)
    |> send_script_action(:short)

    # full urls
    |> list_action()
    |> certificate_auth_action()
    |> general_actions(:long)
    |> import_devices_action()
    |> code_action(:long)
    |> move_action(:long)
    |> reboot_action(:long)
    |> reconnect_action(:long)
    |> upgrade_action(:long)
    |> penalty_action(:long)
    |> send_script_action(:long)
  end

  defp general_actions(openapi, :short) do
    opts = @path_structures[:short]

    path_items = %OpenApiSpex.PathItem{
      get: show_device_action(@path_structures[:short])
    }

    updated_paths = Map.put(openapi.paths, opts.path_prefix, path_items)

    Map.put(openapi, :paths, updated_paths)
  end

  defp general_actions(openapi, :long) do
    opts = @path_structures[:long]

    add_to_paths(openapi, opts.path_prefix, %OpenApiSpex.PathItem{
      get: show_device_action(@path_structures[:long]),
      delete: delete_device_action(@path_structures[:long]),
      put: update_device_action(@path_structures[:long]),
      post: create_device_action(@path_structures[:long])
    })
  end

  defp list_action(openapi) do
    add_to_paths(
      openapi,
      "/api/orgs/{org_name}/products/{product_name}/devices",
      %OpenApiSpex.PathItem{
        get:
          device_operation(
            "List Devices",
            :index,
            [
              @organization_parameter,
              @product_parameter,
              @sort_by_parameter,
              @sort_direction_parameter,
              @pagination_parameter,
              @filters_parameter
            ],
            ["Devices"],
            response: @device_list_response
          )
      }
    )
  end

  def show_device_action(opts) do
    device_operation("Show a Device", :show, opts.parameters, opts.tags,
      response: Map.merge(@device_response, @not_found_error)
    )
  end

  def delete_device_action(opts) do
    device_operation("Delete a Device", :delete, opts.parameters, opts.tags,
      response: Map.merge(@no_content_response, @not_found_error)
    )
  end

  def create_device_action(opts) do
    request_body =
      request_body(
        "Device creation request body",
        "application/json",
        DeviceSchemas.DeviceCreationRequest,
        required: true
      )

    device_operation("Create a Device", :create, opts.parameters, opts.tags,
      request_body: request_body,
      response: Map.merge(@device_creation_response, @validation_error)
    )
  end

  def import_devices_action(openapi) do
    opts = @path_structures[:long]

    request_body =
      request_body(
        "Certificate manifest",
        "application/json",
        DeviceSchemas.DeviceBulkImport,
        required: true
      )

    import_operation =
      device_operation(
        "Bulk create Devices from a manifest. Only a Microchip Trust and Go manifest is currently supported.",
        :bulk_import,
        [@organization_parameter, @product_parameter],
        opts.tags,
        request_body: request_body,
        response: Map.merge(@no_content_response, @validation_error)
      )

    add_to_paths(openapi, "/api/orgs/{org_name}/products/{product_name}/devices/import", %OpenApiSpex.PathItem{
      post: import_operation
    })
  end

  def update_device_action(opts) do
    request_body =
      request_body(
        "Device update request body",
        "application/json",
        DeviceSchemas.DeviceUpdateRequest,
        required: true
      )

    device_operation("Update a Device", :update, opts.parameters, opts.tags,
      request_body: request_body,
      response: Map.merge(@device_response, Map.merge(@not_found_error, @validation_error))
    )
  end

  def code_action(openapi, path_structure) do
    opts = @path_structures[path_structure]

    request_body =
      request_body(
        "Code execution request body",
        "application/json",
        DeviceSchemas.DeviceCodeRequest,
        required: true
      )

    code_operation =
      device_operation(
        "Request a Device run some Elixir code in it's console connection",
        :code,
        opts.parameters,
        opts.tags,
        request_body: request_body,
        response: Map.merge(@no_content_response, @not_found_error)
      )

    add_to_paths(openapi, "#{opts.path_prefix}/code", %OpenApiSpex.PathItem{
      post: code_operation
    })
  end

  def move_action(openapi, path_structure) do
    opts = @path_structures[path_structure]

    query_parameters = [
      %OpenApiSpex.Parameter{
        name: :new_org_name,
        in: :query,
        description: "New Organization Name",
        required: true,
        schema: %OpenApiSpex.Schema{type: :string},
        example: "new_example_org"
      },
      %OpenApiSpex.Parameter{
        name: :new_product_name,
        in: :query,
        description: "New Product Name",
        required: true,
        schema: %OpenApiSpex.Schema{type: :string},
        example: "new_example_product"
      }
    ]

    move_operation =
      device_operation(
        "Move a Device to a different Product",
        :move,
        opts.parameters ++ query_parameters,
        opts.tags,
        response: Map.merge(@device_response, @not_found_error)
      )

    add_to_paths(openapi, "#{opts.path_prefix}/move", %OpenApiSpex.PathItem{
      post: move_operation
    })
  end

  def reboot_action(openapi, path_structure) do
    opts = @path_structures[path_structure]

    reboot_operation =
      device_operation(
        "Request a Device reboot",
        :reboot,
        opts.parameters,
        opts.tags,
        response: Map.merge(@no_content_response, @not_found_error)
      )

    add_to_paths(openapi, "#{opts.path_prefix}/reboot", %OpenApiSpex.PathItem{
      post: reboot_operation
    })
  end

  def reconnect_action(openapi, path_structure) do
    opts = @path_structures[path_structure]

    reconnect_operation =
      device_operation(
        "Request a Device reconnect",
        :reconnect,
        opts.parameters,
        opts.tags,
        response: Map.merge(@no_content_response, @not_found_error)
      )

    add_to_paths(openapi, "#{opts.path_prefix}/reconnect", %OpenApiSpex.PathItem{
      post: reconnect_operation
    })
  end

  def upgrade_action(openapi, path_structure) do
    opts = @path_structures[path_structure]

    request_body =
      request_body(
        "Firmware upgrade request body",
        "application/json",
        DeviceSchemas.DeviceUpgradeRequest,
        required: true
      )

    upgrade_operation =
      device_operation(
        "Request a Device upgrade to a different Firmware",
        :upgrade,
        opts.parameters,
        opts.tags,
        request_body: request_body,
        response: Map.merge(@no_content_response, Map.merge(@not_found_error, @validation_error))
      )

    add_to_paths(openapi, "#{opts.path_prefix}/upgrade", %OpenApiSpex.PathItem{
      post: upgrade_operation
    })
  end

  def penalty_action(openapi, path_structure) do
    opts = @path_structures[path_structure]

    penalty_operation =
      device_operation(
        "Clear the penalty box for a Device",
        :penalty,
        opts.parameters,
        opts.tags,
        response: Map.merge(@no_content_response, @not_found_error)
      )

    add_to_paths(openapi, "#{opts.path_prefix}/penalty", %OpenApiSpex.PathItem{
      delete: penalty_operation
    })
  end

  defp send_script_action(openapi, path_structure) do
    opts = @path_structures[path_structure]

    additional_parameters = [
      %OpenApiSpex.Parameter{
        name: :name_or_id,
        in: :path,
        description: "Support Script Name or ID. Name takes priority.",
        required: true,
        schema: %OpenApiSpex.Schema{
          oneOf: [
            %OpenApiSpex.Schema{type: :string},
            %OpenApiSpex.Schema{type: :integer}
          ]
        },
        example: "my-script"
      },
      %OpenApiSpex.Parameter{
        name: :timeout,
        in: :query,
        description: "How long to wait for a device response in milliseconds",
        required: false,
        schema: %OpenApiSpex.Schema{type: :integer},
        example: "10000"
      }
    ]

    response =
      Map.merge(
        %{200 => response("Script output", "text/plain", nil)},
        @not_found_error
      )

    send_script_operation =
      script_operation(
        "Send a Support Script to a Device",
        :send,
        opts.parameters ++ additional_parameters,
        opts.tags,
        response: response
      )

    add_to_paths(
      openapi,
      "#{opts.path_prefix}/scripts/{name_or_id}",
      %OpenApiSpex.PathItem{post: send_script_operation}
    )
  end

  defp certificate_auth_action(openapi) do
    request_body =
      request_body(
        "Device certificate auth request body",
        "application/json",
        DeviceCertificateSchemas.DeviceCertificateAuthRequest,
        required: true
      )

    auth_operation =
      device_operation(
        "Test a Devices Certificate authentication",
        :auth,
        [@organization_parameter, @product_parameter],
        ["Devices"],
        request_body: request_body,
        response: @device_response
      )

    add_to_paths(
      openapi,
      "/api/orgs/{org_name}/products/{product_name}/devices/auth",
      %OpenApiSpex.PathItem{post: auth_operation}
    )
  end

  defp device_operation(summary, operation_id, parameters, tags, opts) do
    %OpenApiSpex.Operation{
      tags: tags,
      summary: summary,
      operationId: "NervesHubWeb.API.DevicesController.#{operation_id}",
      parameters: parameters,
      requestBody: opts[:request_body],
      responses: Map.merge(@common_errors, opts[:response] || %{}),
      callbacks: %{},
      security: [%{"bearer_auth" => []}],
      extensions: %{}
    }
  end

  defp script_operation(summary, operation_id, parameters, tags, opts) do
    %OpenApiSpex.Operation{
      tags: tags,
      summary: summary,
      operationId: "NervesHubWeb.API.ScriptController.#{operation_id}",
      parameters: parameters,
      requestBody: opts[:request_body],
      responses: Map.merge(@common_errors, opts[:response] || %{}),
      callbacks: %{},
      security: [%{"bearer_auth" => []}],
      extensions: %{}
    }
  end

  defp add_to_paths(openapi, path, path_item) do
    updated_paths = Map.put(openapi.paths, path, path_item)

    Map.put(openapi, :paths, updated_paths)
  end
end

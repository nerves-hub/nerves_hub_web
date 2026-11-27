defmodule NervesHubWeb.API.OpenAPI.DeviceControllerSpecs do
  import OpenApiSpex.Operation, only: [request_body: 4, response: 3]

  alias NervesHub.Devices.DeviceFiltering
  alias NervesHubWeb.API.OpenAPI.SchemaHelpers
  alias NervesHubWeb.API.Schemas.DeviceCertificateSchemas
  alias NervesHubWeb.API.Schemas.DeviceSchemas
  alias NervesHubWeb.API.Schemas.ErrorSchemas

  @organization_parameter SchemaHelpers.org_param()
  @product_parameter SchemaHelpers.product_param()
  @device_parameter SchemaHelpers.device_param()
  @pagination_parameter SchemaHelpers.pagination_param(10)

  @sort_by_parameter %OpenApiSpex.Parameter{
    name: :sort,
    description: "The field to sort by. Any other is refused with a 422.",
    in: :query,
    required: false,
    schema: %OpenApiSpex.Schema{
      type: :string,
      enum: Enum.map(DeviceFiltering.sort_fields(), &Atom.to_string/1),
      default: "identifier"
    },
    example: "identifier"
  }

  @sort_direction_parameter %OpenApiSpex.Parameter{
    name: :sort_direction,
    description: "The direction to sort in. Any other is refused with a 422.",
    in: :query,
    required: false,
    schema: %OpenApiSpex.Schema{type: :string, enum: ["asc", "desc"], default: "asc"},
    example: "asc"
  }

  @device_response %{
    200 => response("Device Response", "application/json", DeviceSchemas.DeviceResponse)
  }

  # An update answers 201 rather than 200. That is what the server has always
  # sent, so it is documented as it is rather than changed under clients.
  @device_update_response %{
    201 => response("Device Response", "application/json", DeviceSchemas.DeviceResponse)
  }

  @device_creation_response %{
    201 => response("Device Response", "application/json", DeviceSchemas.DeviceCreateResponse)
  }

  @device_list_response %{
    200 => response("Device List Response", "application/json", DeviceSchemas.DeviceListResponse)
  }

  @no_content_response %{
    204 => %OpenApiSpex.Response{description: "No content"}
  }

  @certificate_auth_refused %{
    403 => response("Forbidden", "application/json", DeviceCertificateSchemas.DeviceCertificateAuthRefused)
  }

  # The import carries on in the background after the response, so a 201 says
  # the manifest was accepted, not that every device in it was created. The
  # body is empty.
  @bulk_import_response %{
    201 => %OpenApiSpex.Response{description: "Manifest accepted; the devices are created in the background"}
  }

  @bulk_import_headers [
    %OpenApiSpex.Parameter{
      name: :format,
      in: :header,
      description: "The manifest's format",
      required: false,
      schema: %OpenApiSpex.Schema{type: :string, enum: ["microchip_trust_and_go"], default: "microchip_trust_and_go"}
    },
    %OpenApiSpex.Parameter{
      name: :tags,
      in: :header,
      description: "Comma-separated tags to give every device the manifest creates",
      required: false,
      schema: %OpenApiSpex.Schema{type: :string},
      example: "prod,batch-12"
    }
  ]

  @common_errors SchemaHelpers.common_errors()
  @not_found_error SchemaHelpers.not_found_error()
  @validation_error SchemaHelpers.validation_error()
  @query_param_error SchemaHelpers.query_param_error()

  # Actions that reach the device refuse a soft-deleted one; see
  # `NervesHubWeb.API.Plugs.RefuseDeletedDevice`.
  @device_deleted_error %{
    422 => response("Device is deleted and must be restored first", "application/json", ErrorSchemas.ErrorResponse)
  }

  @already_updating_error %{
    409 => response("Device is already updating", "application/json", ErrorSchemas.ErrorResponse)
  }

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
      get: show_device_action(@path_structures[:short], :short)
    }

    updated_paths = Map.put(openapi.paths, opts.path_prefix, path_items)

    Map.put(openapi, :paths, updated_paths)
  end

  defp general_actions(openapi, :long) do
    opts = @path_structures[:long]

    add_to_paths(openapi, opts.path_prefix, %OpenApiSpex.PathItem{
      get: show_device_action(@path_structures[:long], :long),
      delete: delete_device_action(@path_structures[:long]),
      put: update_device_action(@path_structures[:long])
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
              filters_parameter()
            ],
            ["Devices"],
            response: Map.merge(@device_list_response, @query_param_error)
          ),
        post: create_device_action()
      }
    )
  end

  def show_device_action(opts, path_structure) do
    device_operation("Show a Device", :show, opts.parameters, opts.tags,
      path_structure: path_structure,
      response: Map.merge(@device_response, @not_found_error)
    )
  end

  def delete_device_action(opts) do
    device_operation("Delete a Device", :delete, opts.parameters, opts.tags,
      response: Map.merge(@no_content_response, @not_found_error)
    )
  end

  def create_device_action() do
    request_body =
      request_body(
        "Device creation request body",
        "application/json",
        DeviceSchemas.DeviceCreationRequest,
        required: true
      )

    device_operation("Create a Device", :create, [@organization_parameter, @product_parameter], ["Devices"],
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
        "Bulk create Devices from a manifest. Only a Microchip Trust and Go manifest is currently supported. " <>
          "The manifest is read before the import starts: an unknown format, or an entry that can't be read, " <>
          "gets a 422 keyed by where each problem is, such as `entries[3].payload`, and no device is created.",
        :bulk_import,
        [@organization_parameter, @product_parameter | @bulk_import_headers],
        opts.tags,
        request_body: request_body,
        response: Map.merge(@bulk_import_response, @validation_error)
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
      response: Map.merge(@device_update_response, Map.merge(@not_found_error, @validation_error))
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
        path_structure: path_structure,
        request_body: request_body,
        response: Map.merge(@no_content_response, Map.merge(@not_found_error, @device_deleted_error))
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
        path_structure: path_structure,
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
        path_structure: path_structure,
        response: Map.merge(@no_content_response, Map.merge(@not_found_error, @device_deleted_error))
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
        path_structure: path_structure,
        response: Map.merge(@no_content_response, Map.merge(@not_found_error, @device_deleted_error))
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
        path_structure: path_structure,
        request_body: request_body,
        response:
          @no_content_response
          |> Map.merge(@not_found_error)
          |> Map.merge(@validation_error)
          |> Map.merge(@already_updating_error)
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
        path_structure: path_structure,
        response: Map.merge(@no_content_response, Map.merge(@not_found_error, @device_deleted_error))
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
        %{200 => response("Script output", "text/plain", %OpenApiSpex.Schema{type: :string})},
        Map.merge(@not_found_error, @device_deleted_error)
      )

    send_script_operation =
      script_operation(
        "Send a Support Script to a Device",
        :send,
        opts.parameters ++ additional_parameters,
        opts.tags,
        path_structure: path_structure,
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
        "Test a Devices Certificate authentication. Only a device in the product in the path matches.",
        :auth,
        [@organization_parameter, @product_parameter],
        ["Devices"],
        request_body: request_body,
        response: Map.merge(@device_response, Map.merge(@certificate_auth_refused, @validation_error))
      )

    add_to_paths(
      openapi,
      "/api/orgs/{org_name}/products/{product_name}/devices/auth",
      %OpenApiSpex.PathItem{post: auth_operation}
    )
  end

  # An operation published under both the short and long URL structures needs a
  # distinct operationId for each, since OpenAPI requires them to be unique
  # document-wide.
  defp operation_id(controller, action, nil), do: "#{controller}.#{action}"
  defp operation_id(controller, action, path_structure), do: "#{controller}.#{action}.#{path_structure}"

  # The filters `DeviceFiltering.cast_filters/1` takes, but for two. It takes
  # the web UI's `is_pinned`, but pins are each web UI user's own, so the API's
  # list ignores it. `healthy` filters nothing anywhere.
  defp filters_parameter() do
    %OpenApiSpex.Parameter{
      name: :filters,
      description:
        "Filtering, as the web UI's devices list filters. Each filter given narrows the list. " <>
          "A key that isn't a filter, or a value its filter can't take, is refused with a 422. " <>
          "An empty value leaves its filter unset.",
      in: :query,
      style: :deepObject,
      required: false,
      schema: %OpenApiSpex.Schema{
        type: :object,
        additionalProperties: false,
        properties: %{
          advanced_query: %OpenApiSpex.Schema{
            type: :string,
            description: """
            A query in the device list's advanced query language, the same one the
            web UI's search bar uses. Values are quoted; expressions combine with
            `and`/`or`/`not` and parentheses. Custom health metrics are queried as
            `metric:<key>` with numeric comparisons against each device's latest
            reading. Input that doesn't look like a query expression is treated as
            a free-text search across the device's textual fields; an invalid
            query expression is rejected with a 422 and the parse error.

            Examples:
            * `metric:cpu_temp > 70`
            * `connection = "connected" and tags contains "prod"`
            * `health_status != "healthy" or alarm_status = "with"`
            * `metric:battery_soc < 20 and updates = "enabled"`
            * `firmware_validation_status = "not_validated"`
            * `signer_ca = "1234567890"`
            """,
            example: ~s|metric:cpu_temp > 70 and connection = "connected"|
          },
          alarm:
            any_of(
              "Devices with a raised alarm whose name contains this. Several, comma-separated, match any of them.",
              "SomeAlarm"
            ),
          alarm_status: one_or_more(:alarm_status, "Devices with any alarm raised, or with none."),
          connection:
            one_or_more(
              :connection,
              "`offline` is every device not connected now, where `disconnected` leaves out devices that never " <>
                "connected. `asleep` is a device whose last connection ended with it going to sleep."
            ),
          connection_type: one_or_more(:connection_type, "How the device last connected."),
          deployment_id: %OpenApiSpex.Schema{
            type: :integer,
            description: "Devices in the deployment group with this ID, or `-1` for devices in none.",
            minimum: -1,
            example: 12
          },
          display_deleted: %OpenApiSpex.Schema{
            type: :string,
            enum: DeviceFiltering.filter_values(:display_deleted),
            default: "exclude",
            description: """
            Which soft-deleted devices to list: `exclude` leaves them out, `include`
            lists them with the rest, and `only` lists them alone. Each device says
            whether it is `deleted`. An `advanced_query` that names `deleted`
            decides instead.
            """
          },
          firmware_validation_status:
            one_or_more(:firmware_validation_status, "Whether the device's firmware is validated."),
          firmware_version:
            any_of(
              "Devices running one of these firmware versions, comma-separated, or `Unknown` for none reported.",
              "1.10.0"
            ),
          has_no_tags: %OpenApiSpex.Schema{type: :boolean, description: "`true` lists only devices with no tags."},
          health_status: one_or_more(:health_status, "The device's health, judged by its product's health profile."),
          identifier: %OpenApiSpex.Schema{
            type: :string,
            description: "Devices whose identifier contains this.",
            example: "sn123"
          },
          metrics_key: %OpenApiSpex.Schema{
            type: :string,
            description:
              "A custom health metric, whose latest reading on each device is compared with `metrics_value`. " <>
                "Applied only with `metrics_value`.",
            example: "cpu_temp"
          },
          metrics_operator: %OpenApiSpex.Schema{
            type: :string,
            enum: DeviceFiltering.filter_values(:metrics_operator),
            default: "gt",
            description: "Whether the reading is greater (`gt`) or less (`lt`) than `metrics_value`."
          },
          metrics_value: %OpenApiSpex.Schema{
            type: :number,
            description: "The number `metrics_key`'s reading is compared with.",
            example: 70
          },
          only_updating: %OpenApiSpex.Schema{
            type: :boolean,
            description: "`true` lists only devices installing an update now."
          },
          platform: %OpenApiSpex.Schema{
            type: :string,
            description: "Devices whose firmware is for this platform, or `Unknown` for none reported.",
            example: "rpi4"
          },
          reason: %OpenApiSpex.Schema{
            type: :string,
            enum: DeviceFiltering.filter_values(:reason),
            description:
              "Devices that need attention for this reason: unhealthy, updates on hold after repeated failures, " <>
                "or not seen in #{DeviceFiltering.not_seen_days()} days or more."
          },
          search: %OpenApiSpex.Schema{
            type: :string,
            description: "Devices whose identifier, firmware version, platform or tags contain this.",
            example: "sn123"
          },
          signer_ca: %OpenApiSpex.Schema{
            type: :string,
            description:
              "The serial of the CA which signed the device's certificate, or `:not_set` for devices with no certificate from a registered CA.",
            example: "1234567890"
          },
          state: %OpenApiSpex.Schema{
            type: :string,
            enum: DeviceFiltering.filter_values(:state),
            description:
              "One of the web UI's tabs: devices that need attention (see `reason`), connected now, " <>
                "installing an update now, or not connected now."
          },
          tags: %OpenApiSpex.Schema{
            type: :string,
            description:
              "Tags, comma-separated: devices with every one of them. A tag can't contain a space, " <>
                "and matches any of a device's tags containing it.",
            example: "prod,staging"
          },
          updates:
            one_or_more(:updates, "How the device takes updates, or `updating` for one installing an update now.")
        }
      }
    }
  end

  # A filter taking one or more of the choices `DeviceFiltering.filter_values/1`
  # lists. An `enum` would refuse several.
  defp one_or_more(key, description) do
    values = DeviceFiltering.filter_values(key)

    %OpenApiSpex.Schema{
      type: :string,
      description:
        "#{description} One or more of #{Enum.map_join(values, ", ", &"`#{&1}`")}, comma-separated: " <>
          "a device matches any of them.",
      example: hd(values)
    }
  end

  defp any_of(description, example), do: %OpenApiSpex.Schema{type: :string, description: description, example: example}

  defp device_operation(summary, operation_id, parameters, tags, opts) do
    %OpenApiSpex.Operation{
      tags: tags,
      summary: summary,
      operationId: operation_id("NervesHubWeb.API.DevicesController", operation_id, opts[:path_structure]),
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
      operationId: operation_id("NervesHubWeb.API.ScriptController", operation_id, opts[:path_structure]),
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

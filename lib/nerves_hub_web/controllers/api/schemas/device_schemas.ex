defmodule NervesHubWeb.API.Schemas.DeviceSchemas do
  alias NervesHubWeb.API.Schemas.DeviceSharedSecretSchemas.DeviceSharedSecretWithSecret
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule Device do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        identifier: %Schema{type: :string},
        description: %Schema{type: :string},
        tags: %Schema{type: :string},
        online: %Schema{type: :boolean},
        connection_status: %Schema{type: :string, enum: ["connected", "disconnected"]},
        firmware_metadata: %Schema{
          type: :object,
          properties: %{
            id: %Schema{type: :string},
            misc: %Schema{type: :string},
            uuid: %Schema{type: :string},
            author: %Schema{type: :string},
            product: %Schema{type: :string},
            version: %Schema{type: :string},
            platform: %Schema{type: :string},
            description: %Schema{type: :string},
            architecture: %Schema{type: :string},
            fwup_version: %Schema{type: :string},
            vcs_identifier: %Schema{type: :string}
          }
        },
        version: %Schema{type: :string},
        deployment_group: %Schema{
          type: :object,
          properties: %{
            name: %Schema{type: :string},
            is_active: %Schema{type: :boolean},
            firmware_uuid: %Schema{type: :string},
            firmware_version: %Schema{type: :string}
          }
        },
        updates_enabled: %Schema{
          type: :boolean,
          description: "Whether the device takes updates at all. False only when update_mode is off."
        },
        update_mode: %Schema{
          type: :string,
          description:
            "How the device receives firmware. automatic: pushed by its deployment group. device_managed: the device asks for updates itself. off: neither, only a manual push.",
          enum: ["off", "automatic", "device_managed"]
        },
        managed_updates_allowed: %Schema{
          type: :boolean,
          description: "Whether the device may move itself between automatic and device_managed."
        },
        updates_blocked_until: %Schema{
          type: :string,
          description: "Device penalty box expiration timestamp",
          format: :"date-time"
        },
        org_name: %Schema{type: :string},
        product_name: %Schema{type: :string},
        last_communication: %Schema{
          type: :string,
          format: :"date-time",
          deprecated: true
        }
      },
      example: %{
        "identifier" => "abc123",
        "description" => "A great device",
        "tags" => "prod, customerABC",
        "online" => true,
        "connection_status" => "connected",
        "firmware_metadata" => %{
          "id" => "3f2264c3-cc52-2ba9-b77d-e441f8bb91b6",
          "misc" => "extra comments",
          "uuid" => "6fd2bbc8-52b8-4826-5c2a-189968d0de23",
          "author" => "",
          "product" => "AmazingProduct",
          "version" => "1.2.3",
          "platform" => "rpi5",
          "description" => "Prod Firmware",
          "architecture" => "arm",
          "fwup_version" => "1.10.1",
          "vcs_identifier" => ""
        },
        "version" => "1.2.3",
        "deployment_group" => %{
          "firmware_uuid" => "6fd2bbc8-52b8-4826-5c2a-189968d0de23",
          "firmware_version" => "1.2.3",
          "is_active" => true,
          "name" => "Prod Deployment"
        },
        "updates_enabled" => true,
        "updates_blocked_until" => "2050-04-20T00:33:09Z",
        "org_name" => "BigCompany",
        "product_name" => "AmazingProduct",
        "last_communication" => "2050-04-20T00:33:09Z"
      }
    })
  end

  defmodule DeviceResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for a single Device",
      type: :object,
      properties: %{
        data: Device
      },
      example: %{
        "data" => %{
          "identifier" => "abc123",
          "description" => "A great device",
          "tags" => "prod, customerABC",
          "online" => true,
          "connection_status" => "connected",
          "firmware_metadata" => %{
            "id" => "3f2264c3-cc52-2ba9-b77d-e441f8bb91b6",
            "misc" => "extra comments",
            "uuid" => "6fd2bbc8-52b8-4826-5c2a-189968d0de23",
            "author" => "",
            "product" => "AmazingProduct",
            "version" => "1.2.3",
            "platform" => "rpi5",
            "description" => "Prod Firmware",
            "architecture" => "arm",
            "fwup_version" => "1.10.1",
            "vcs_identifier" => ""
          },
          "version" => "1.2.3",
          "deployment_group" => %{
            "firmware_uuid" => "6fd2bbc8-52b8-4826-5c2a-189968d0de23",
            "firmware_version" => "1.2.3",
            "is_active" => true,
            "name" => "Prod Deployment"
          },
          "updates_enabled" => true,
          "updates_blocked_until" => "2050-04-20T00:33:09Z",
          "org_name" => "BigCompany",
          "product_name" => "AmazingProduct",
          "last_communication" => "2050-04-20T00:33:09Z"
        }
      }
    })
  end

  defmodule DeviceCreateResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for a created Device",
      type: :object,
      properties: %{
        data: %Schema{
          allOf: [
            Device,
            %Schema{
              type: :object,
              properties: %{
                shared_secret: %Schema{
                  allOf: [DeviceSharedSecretWithSecret],
                  description: "Only present when the device was created with `shared_secret: true`"
                }
              }
            }
          ]
        }
      },
      example:
        put_in(
          DeviceResponse.schema().example,
          ["data", "shared_secret"],
          DeviceSharedSecretWithSecret.schema().example
        )
    })
  end

  defmodule DeviceListResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for multiple Devices",
      type: :object,
      properties: %{
        data: %Schema{
          description: "The Device schema",
          type: :array,
          items: Device
        },
        pagination: %Schema{
          type: :object,
          properties: %{
            page_number: %Schema{type: :integer},
            page_size: %Schema{type: :integer},
            total_pages: %Schema{type: :integer},
            total_entries: %Schema{type: :integer}
          }
        }
      },
      example: %{
        "data" => [
          %{
            "identifier" => "abc123",
            "description" => "A great device",
            "tags" => "prod, customerABC",
            "online" => true,
            "connection_status" => "connected",
            "firmware_metadata" => %{
              "id" => "3f2264c3-cc52-2ba9-b77d-e441f8bb91b6",
              "misc" => "extra comments",
              "uuid" => "6fd2bbc8-52b8-4826-5c2a-189968d0de23",
              "author" => "",
              "product" => "AmazingProduct",
              "version" => "1.2.3",
              "platform" => "rpi5",
              "description" => "Prod Firmware",
              "architecture" => "arm",
              "fwup_version" => "1.10.1",
              "vcs_identifier" => ""
            },
            "version" => "1.2.3",
            "deployment_group" => %{
              "firmware_uuid" => "6fd2bbc8-52b8-4826-5c2a-189968d0de23",
              "firmware_version" => "1.2.3",
              "is_active" => true,
              "name" => "Prod Deployment"
            },
            "updates_enabled" => true,
            "updates_blocked_until" => "2050-04-20T00:33:09Z",
            "org_name" => "BigCompany",
            "product_name" => "AmazingProduct",
            "last_communication" => "2050-04-20T00:33:09Z"
          },
          %{
            "identifier" => "def456",
            "description" => "Another great device",
            "tags" => "prod, customerDEF",
            "online" => false,
            "connection_status" => "disconnected",
            "firmware_metadata" => %{
              "id" => "3f2264c3-cc52-2ba9-b77d-e441f8bb91b6",
              "misc" => "extra comments",
              "uuid" => "6fd2bbc8-52b8-4826-5c2a-189968d0de23",
              "author" => "",
              "product" => "AmazingProduct",
              "version" => "1.2.3",
              "platform" => "rpi5",
              "description" => "Prod Firmware",
              "architecture" => "arm",
              "fwup_version" => "1.10.1",
              "vcs_identifier" => ""
            },
            "version" => "1.2.3",
            "deployment_group" => %{
              "firmware_uuid" => "6fd2bbc8-52b8-4826-5c2a-189968d0de23",
              "firmware_version" => "1.2.3",
              "is_active" => true,
              "name" => "Prod Deployment"
            },
            "updates_enabled" => true,
            "updates_blocked_until" => "2050-04-20T00:33:09Z",
            "org_name" => "BigCompany",
            "product_name" => "AmazingProduct",
            "last_communication" => "2050-04-20T00:33:09Z"
          }
        ],
        "pagination" => %{
          "page_number" => 1,
          "page_size" => 10,
          "total_pages" => 1,
          "total_entries" => 2
        }
      }
    })
  end

  defmodule DeviceBulkImport do
    OpenApiSpex.schema(%{
      description: "POST body for bulk creating a list of Devices",
      type: :object,
      properties: nil,
      example: ["Please refer to the Microchip Trust and Go Manifest documentation"]
    })
  end

  # The fields a request may set on a device, shared by the create and update
  # bodies. They are what `Device.create_changeset/2` and
  # `Device.update_changeset/2` cast; anything else in a body is ignored.
  defmodule DeviceSettings do
    @moduledoc false

    def properties() do
      %{
        description: %Schema{type: :string},
        tags: %Schema{
          description: "A list of tags, or one comma-separated string of them. A tag cannot contain spaces.",
          oneOf: [
            %Schema{type: :array, items: %Schema{type: :string}},
            %Schema{type: :string}
          ]
        },
        update_mode: %Schema{
          type: :string,
          description:
            "How the device receives firmware. automatic: pushed by its deployment group. device_managed: the device asks for updates itself. off: neither, only a manual push.",
          enum: ["off", "automatic", "device_managed"]
        },
        connecting_code: %Schema{
          type: :string,
          description:
            "Elixir code the device runs on its console each time it connects, after any from its deployment group and release."
        }
      }
    end
  end

  defmodule DeviceCreationRequest do
    OpenApiSpex.schema(%{
      description: """
      POST body for creating a Device. The device belongs to the product in the path and starts with that product's default for whether it may manage its own updates. Fields not listed here are ignored.

      The device's fields are also read from the top level of the body when it has no `device` object.
      """,
      type: :object,
      properties: %{
        device: %Schema{
          type: :object,
          properties: Map.put(DeviceSettings.properties(), :identifier, %Schema{type: :string}),
          required: [:identifier]
        },
        shared_secret: %Schema{
          type: :boolean,
          description:
            "Also create the device's own shared secret, in the same transaction. The key and secret are returned as `data.shared_secret`, the only time the secret is returned. When device shared secrets are not enabled on this platform, the request is refused and no device is created."
        }
      },
      required: [:device],
      example: %{
        "device" => %{
          "identifier" => "abc123",
          "description" => "Example Device",
          "tags" => ["prod", "customerJNK"],
          "update_mode" => "automatic"
        }
      }
    })
  end

  defmodule DeviceUpdateRequest do
    OpenApiSpex.schema(%{
      description: """
      PUT body for updating a Device. Only the fields given are changed, and fields not listed here are ignored.

      The device's fields are also read from the top level of the body when it has no `device` object.
      """,
      type: :object,
      properties: %{
        device: %Schema{
          type: :object,
          properties:
            Map.put(DeviceSettings.properties(), :managed_updates_allowed, %Schema{
              type: :boolean,
              description:
                "Whether the device may move itself between automatic and device_managed. A change is recorded in the audit log. Taking it away does not move a device that is already device_managed; set update_mode for that."
            })
        }
      },
      required: [:device],
      example: %{
        "device" => %{
          "description" => "Example Device",
          "tags" => ["prod", "customerJNK"],
          "update_mode" => "device_managed",
          "managed_updates_allowed" => true
        }
      }
    })
  end

  defmodule DeviceCodeRequest do
    OpenApiSpex.schema(%{
      description: "POST body for sending Elixir code to a Device's console",
      type: :object,
      properties: %{
        code: %Schema{type: :string, description: "Elixir code to execute"}
      },
      required: [:code],
      example: %{
        "code" => "NervesHub.version()"
      }
    })
  end

  defmodule DeviceUpgradeRequest do
    OpenApiSpex.schema(%{
      description: "POST body for upgrading a Device to a specific Firmware",
      type: :object,
      properties: %{
        uuid: %Schema{type: :string, description: "Target firmware UUID", format: :uuid}
      },
      required: [:uuid],
      example: %{
        "uuid" => "d9f8c63a-1234-5678-abcd-ef0123456789"
      }
    })
  end
end

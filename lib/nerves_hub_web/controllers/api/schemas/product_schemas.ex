defmodule NervesHubWeb.API.Schemas.ProductSchemas do
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule Product do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        name: %Schema{
          type: :string,
          pattern: ~r/[a-zA-Z][a-zA-Z0-9_]+/
        },
        require_unique_firmware_version: %Schema{
          type: :boolean,
          description:
            "Reject uploaded firmware whose version already exists for this product's platform and architecture."
        },
        allowed_update_tools: %Schema{
          type: :array,
          items: %Schema{type: :string, enum: ["fwup", "esp-idf", "atomvm", "rauc"]},
          description: """
          The firmware formats this product accepts. `fwup` is always present.

          A format also has to be enabled for the instance before a product can
          list it (`ESP_IDF_FIRMWARE_ENABLED`, `ATOMVM_FIRMWARE_ENABLED` or
          `RAUC_FIRMWARE_ENABLED`).
          """
        },
        allow_unsigned_esp_idf_firmware: %Schema{
          type: :boolean,
          description: """
          Accept ESP-IDF images that carry no Secure Boot v2 signature block.

          This excuses a missing signature and nothing else: an image that does
          carry a signature is always verified against the organization's
          registered signing keys.
          """
        },
        allow_unsigned_atomvm_firmware: %Schema{
          type: :boolean,
          description: """
          Accept AtomVM packbeam archives that carry no signature entry.

          Nothing in the AtomVM toolchain signs by default, so a product built
          without `nh-avm` has no way to sign yet.

          This excuses a missing signature and nothing else: an archive that
          does carry one is always verified against the organization's
          registered signing keys.
          """
        },
        default_managed_updates_allowed: %Schema{
          type: :boolean,
          description: """
          The `managed_updates_allowed` grant a device created in this product
          starts with: whether it may put itself into `device_managed` update
          mode. A device created with its own value keeps that instead.

          Changing this moves no existing device.
          """
        }
      },
      example: %{
        "name" => "Example Product",
        "require_unique_firmware_version" => true,
        "allowed_update_tools" => ["fwup"],
        "allow_unsigned_esp_idf_firmware" => false,
        "allow_unsigned_atomvm_firmware" => false,
        "default_managed_updates_allowed" => false
      }
    })
  end

  defmodule ProductUtilization do
    require OpenApiSpex

    @item_example %{
      "key" => "delta_updates",
      "group" => "recommended",
      "title" => "Delta updates",
      "description" =>
        "Send only what changed between two firmware versions. The firmware has to declare delta sources in fwup.conf, and the deployment group has to have delta updates on.",
      "status" => "todo",
      "summary" => "Delta updates are off for every deployment group that is turned on.",
      "docs_url" => "https://docs.nerves-hub.org/management/delta-updates"
    }

    @example %{
      "score" => %{"done" => 5, "total" => 13},
      "device_auth" => [
        %{"key" => "shared_secret", "label" => "Shared Secret", "level" => "warning", "devices" => 2},
        %{"key" => "local_cert", "label" => "LocalCert", "level" => "good", "devices" => 10},
        %{"key" => "nerves_key", "label" => "NervesKey", "level" => "good", "devices" => 0}
      ],
      "items" => [@item_example]
    }

    def example(), do: @example

    OpenApiSpex.schema(%{
      description: "Which NervesHub features a product is using.",
      type: :object,
      properties: %{
        score: %Schema{
          type: :object,
          description: """
          How many of the scored items are `done`. Scored items are those in
          the `authentication` and `recommended` groups whose status isn't
          `unavailable`.
          """,
          properties: %{
            done: %Schema{type: :integer},
            total: %Schema{type: :integer}
          }
        },
        device_auth: %Schema{
          type: :array,
          description: """
          How the product's devices authenticate, by method. A device with a
          certificate is counted under `nerves_key` when the certificate has
          the shape the NervesKey tooling signs, and under `local_cert`
          otherwise, which includes keys held in a TPM. A device that has
          connected without a certificate is counted under `shared_secret`.
          A device that has never connected and has no certificate is in none
          of them.
          """,
          items: %Schema{
            type: :object,
            properties: %{
              key: %Schema{type: :string, enum: ["shared_secret", "local_cert", "nerves_key"]},
              label: %Schema{type: :string},
              level: %Schema{
                type: :string,
                enum: ["good", "warning"],
                description:
                  "Whether the method is one to move away from (`warning`). A shared secret is `good` when every device using one has a secret of its own, and `warning` when any uses the product's."
              },
              devices: %Schema{type: :integer, description: "Devices using the method."}
            }
          }
        },
        items: %Schema{
          type: :array,
          description: "Every feature checked, in the order it is shown.",
          items: %Schema{
            type: :object,
            properties: %{
              key: %Schema{type: :string, description: "A stable name for the item."},
              group: %Schema{
                type: :string,
                enum: ["authentication", "recommended", "optional"],
                description: "`optional` items are situational and never scored."
              },
              title: %Schema{type: :string},
              description: %Schema{type: :string, description: "What the feature is and what turning it on takes."},
              status: %Schema{
                type: :string,
                enum: ["done", "attention", "todo", "unavailable"],
                description: """
                `done` is in use. `attention` is a warning about something that
                is set up: it is risky, such as a shared secret, or it is on
                and nothing has arrived that would be expected to. `todo` is
                not in use, or not all the way there, and is never a warning.
                `unavailable` means this instance can't offer the feature, so
                it isn't scored.
                """
              },
              summary: %Schema{type: :string, description: "What was found for this product."},
              docs_url: %Schema{type: :string, description: "Where the NervesHub documentation covers the feature."}
            }
          }
        }
      },
      example: @example
    })
  end

  defmodule ProductUtilizationResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for a product's utilization report",
      type: :object,
      properties: %{
        data: ProductUtilization
      },
      example: %{"data" => ProductUtilization.example()}
    })
  end

  defmodule ProductShowResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for a single Product",
      type: :object,
      properties: %{
        data: Product
      },
      example: %{
        "data" => %{
          "name" => "Example Product",
          "require_unique_firmware_version" => true,
          "allowed_update_tools" => ["fwup"],
          "allow_unsigned_esp_idf_firmware" => false,
          "allow_unsigned_atomvm_firmware" => false,
          "default_managed_updates_allowed" => false
        }
      }
    })
  end

  defmodule ProductListResponse do
    OpenApiSpex.schema(%{
      description: "Response schema for multiple products",
      type: :object,
      properties: %{
        data: %Schema{description: "The products details", type: :array, items: Product}
      },
      example: %{
        "data" => [
          %{
            "name" => "Example Product",
            "require_unique_firmware_version" => true,
            "allowed_update_tools" => ["fwup"],
            "allow_unsigned_esp_idf_firmware" => false,
            "allow_unsigned_atomvm_firmware" => false,
            "default_managed_updates_allowed" => false
          },
          %{
            "name" => "Another Example Product",
            "require_unique_firmware_version" => true,
            "allowed_update_tools" => ["fwup", "esp-idf"],
            "allow_unsigned_esp_idf_firmware" => true
          }
        ]
      }
    })
  end

  defmodule ProductCreationRequest do
    OpenApiSpex.schema(%{
      description: """
      POST body for creating a product. Only `name` is read; set the product's other settings
      through an update.
      """,
      type: :object,
      properties: %{
        name: %Schema{type: :string}
      },
      required: [:name],
      example: %{
        "name" => "ExampleProduct"
      }
    })
  end

  defmodule ProductUpdateRequest do
    OpenApiSpex.schema(%{
      description: """
      PUT body for updating a product's settings.

      Every field is optional; only the ones sent are changed. A product cannot
      be renamed here — its name is its identifier in every URL — and sending
      any field not listed below is an error rather than being ignored.
      """,
      type: :object,
      properties: %{
        require_unique_firmware_version: %Schema{type: :boolean},
        allowed_update_tools: %Schema{
          type: :array,
          items: %Schema{type: :string, enum: ["fwup", "esp-idf", "atomvm", "rauc"]}
        },
        allow_unsigned_esp_idf_firmware: %Schema{type: :boolean},
        allow_unsigned_atomvm_firmware: %Schema{type: :boolean},
        default_managed_updates_allowed: %Schema{type: :boolean}
      },
      example: %{
        "allowed_update_tools" => ["fwup", "atomvm"],
        "allow_unsigned_atomvm_firmware" => true
      }
    })
  end
end

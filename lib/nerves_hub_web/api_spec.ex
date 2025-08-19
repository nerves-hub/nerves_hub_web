defmodule NervesHubWeb.ApiSpec do
  alias OpenApiSpex.Components
  alias OpenApiSpex.Info
  alias OpenApiSpex.MediaType
  alias OpenApiSpex.OpenApi
  alias OpenApiSpex.Operation
  alias OpenApiSpex.PathItem
  alias OpenApiSpex.Paths
  alias OpenApiSpex.Response
  alias OpenApiSpex.Schema
  alias OpenApiSpex.SecurityScheme
  alias OpenApiSpex.Server
  alias OpenApiSpex.Tag

  alias NervesHubWeb.API.OpenAPI.DeviceControllerSpecs
  alias NervesHubWeb.Endpoint
  alias NervesHubWeb.Router

  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      servers: [
        # Populate the Server info from a phoenix endpoint
        Server.from_endpoint(Endpoint)
      ],
      info: %Info{
        title: "#{Application.get_env(:nerves_hub, :support_email_platform_name)} API",
        version: "2.0.0"
      },
      # Populate the paths from a phoenix router
      paths: Router |> Paths.from_router() |> add_status_paths(),
      components: %Components{
        securitySchemes: %{
          "bearer_auth" => %SecurityScheme{
            type: "http",
            scheme: "bearer"
          }
        },
        responses: %{
          "unprocessable_entity" => %Response{
            description: "Unprocessable Entity",
            content: %{"application/json" => %MediaType{schema: %Schema{type: :object}}}
          }
        }
      },
      security: [
        %{
          "bearer" => []
        }
      ],
      tags: [
        %Tag{
          name: "Auth",
          description: "User authentication and API token creation"
        },
        %Tag{
          name: "CA Certificates",
          description: "Organization Certificate Authority management"
        },
        %Tag{
          name: "Devices",
          description:
            "Device management, including action requests eg. upgrade, reboot, reconnect"
        },
        %Tag{
          name: "Devices (short URL)",
          description:
            "Device management, including action requests eg. upgrade, reboot, reconnect"
        },
        %Tag{
          name: "Device Certificates",
          description: "Device Certificate management"
        },
        %Tag{
          name: "Deployment Groups",
          description: "Operations related to Deployment Groups"
        },
        %Tag{
          name: "Firmwares",
          description: "Firmware uploading and management"
        },
        %Tag{
          name: "Organization Members",
          description: "Organization User membership"
        },
        %Tag{
          name: "Products",
          description: "Product management"
        },
        %Tag{
          name: "Signing Keys",
          description: "Organization Signing Key management"
        },
        %Tag{
          name: "Status",
          description: "Application healthcheck"
        },
        %Tag{
          name: "Support Scripts",
          description: "Organization Support Script management"
        }
      ]
    }
    |> DeviceControllerSpecs.add_operations()
    # Discover request/response schemas from path specs
    |> OpenApiSpex.resolve_schema_modules()
  end

  # The `/status/alive` path is handled by the `NervesHubWeb.Plugs.ImAlive` plug
  defp add_status_paths(main_paths) do
    status_path = "/status/alive"

    status_spec = %{
      status_path => %PathItem{
        get: %Operation{
          summary: "Check application status",
          description:
            "Provides a simple health check to verify that the application is running, responsive, and can connect to the database.",
          tags: ["Status"],
          operationId: "Status.alive",
          responses: %{
            "200" => %Response{
              description: "The application is running and the database is reachable.",
              content: %{
                "text/plain" => %MediaType{
                  schema: %Schema{type: :string, example: "Hello, Friend!"}
                }
              }
            },
            "500" => %Response{
              description: "The application is running but the database is unreachable.",
              content: %{
                "text/plain" => %MediaType{
                  schema: %Schema{type: :string, example: "Sorry, Friend :("}
                }
              }
            }
          },
          # This endpoint does not require authentication, so we override the global security
          security: []
        }
      }
    }

    Map.merge(main_paths, status_spec)
  end
end

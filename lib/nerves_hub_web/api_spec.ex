defmodule NervesHubWeb.ApiSpec do
  alias OpenApiSpex.Components
  alias OpenApiSpex.Info
  alias OpenApiSpex.MediaType
  alias OpenApiSpex.OpenApi
  alias OpenApiSpex.Paths
  alias OpenApiSpex.Response
  alias OpenApiSpex.Schema
  alias OpenApiSpex.SecurityScheme
  alias OpenApiSpex.Server
  alias OpenApiSpex.Tag

  alias NervesHubWeb.API.OpenAPI.DeviceControllerSpecs
  alias NervesHubWeb.Endpoint
  alias NervesHubWeb.Router
  alias NervesHubWeb.Plugs.ImAlive

  @behaviour OpenApi

  @impl OpenApi
  def spec() do
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
      paths: set_paths(),
      components: %Components{
        responses: %{
          "unprocessable_entity" => %Response{
            content: %{"application/json" => %MediaType{schema: %Schema{type: :object}}},
            description: "Unprocessable Entity"
          }
        },
        securitySchemes: %{
          "bearer_auth" => %SecurityScheme{
            scheme: "bearer",
            type: "http"
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
          description: "User authentication and API token creation",
          name: "Auth"
        },
        %Tag{
          description: "Organization Certificate Authority management",
          name: "CA Certificates"
        },
        %Tag{
          description: "Device management, including action requests eg. upgrade, reboot, reconnect",
          name: "Devices"
        },
        %Tag{
          description: "Device management, including action requests eg. upgrade, reboot, reconnect",
          name: "Devices (short URL)"
        },
        %Tag{
          description: "Device Certificate management",
          name: "Device Certificates"
        },
        %Tag{
          description: "Operations related to Deployment Groups",
          name: "Deployment Groups"
        },
        %Tag{
          description: "Firmware uploading and management",
          name: "Firmwares"
        },
        %Tag{
          description: "Organization User membership",
          name: "Organization Members"
        },
        %Tag{
          description: "Product management",
          name: "Products"
        },
        %Tag{
          description: "Organization Signing Key management",
          name: "Signing Keys"
        },
        %Tag{
          description: "Application healthcheck",
          name: "Status"
        },
        %Tag{
          description: "Organization Support Script management",
          name: "Support Scripts"
        }
      ]
    }
    |> DeviceControllerSpecs.add_operations()
    # Discover request/response schemas from path specs
    |> OpenApiSpex.resolve_schema_modules()
  end

  defp set_paths() do
    Router
    |> Paths.from_router()
    |> Map.merge(ImAlive.status_path_spec())
  end
end

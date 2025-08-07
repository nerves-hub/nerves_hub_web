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
      paths: Paths.from_router(Router),
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
          name: "Support Scripts",
          description: "Organization Support Script management"
        }
      ]
    }
    |> DeviceControllerSpecs.add_operations()
    # Discover request/response schemas from path specs
    |> OpenApiSpex.resolve_schema_modules()
  end
end

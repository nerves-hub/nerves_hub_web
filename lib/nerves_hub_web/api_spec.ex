defmodule NervesHubWeb.ApiSpec do
  @behaviour OpenApiSpex.OpenApi

  alias NervesHubWeb.API.OpenAPI.DeviceControllerSpecs
  alias NervesHubWeb.API.OpenAPI.SupportScriptControllerSpecs
  alias NervesHubWeb.Endpoint
  alias NervesHubWeb.Plugs.ImAlive
  alias NervesHubWeb.Router
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

  @impl OpenApi
  def spec() do
    %OpenApi{
      servers: [
        # Populate the Server info from a phoenix endpoint
        Server.from_endpoint(Endpoint)
      ],
      info: %Info{
        title: "#{Application.get_env(:nerves_hub, :support_email_platform_name)} API",
        version: "2.0.0",
        description: ~s"""
        The #{Application.get_env(:nerves_hub, :support_email_platform_name)} API gives users full access to their
        Orgs, Products, and corresponding Device fleets.

        The API can be used to integrate with your own systems, providing full access to your Product and Device data.

        The API is documented using the OpenAPI 3.0 specification.
        """
      },
      # Populate the paths from a phoenix router
      paths: set_paths(),
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
          "bearer_auth" => []
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
          description: "Device management, including action requests eg. upgrade, reboot, reconnect"
        },
        %Tag{
          name: "Devices (short URL)",
          description: "Device management, including action requests eg. upgrade, reboot, reconnect"
        },
        %Tag{
          name: "Device Certificates",
          description: "Device Certificate management"
        },
        %Tag{
          name: "Deployment Groups",
          description: "Deployment Group and release management"
        },
        %Tag{
          name: "Firmwares",
          description: "Firmware uploading and management"
        },
        %Tag{
          name: "Organizations",
          description: "Organization management"
        },
        %Tag{
          name: "Organization Members",
          description: "Organization User membership management"
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
          description: "Product Support Script management"
        },
        %Tag{
          name: "Platform Status",
          description: "Platform healthcheck"
        }
      ]
    }
    |> DeviceControllerSpecs.add_operations()
    |> SupportScriptControllerSpecs.add_operations()
    # Discover request/response schemas from path specs
    |> OpenApiSpex.resolve_schema_modules()
  end

  defp set_paths() do
    Router
    |> Paths.from_router()
    |> Map.merge(ImAlive.status_path_spec())
  end
end

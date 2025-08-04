defmodule NervesHubWeb.HealthcheckController do
  use NervesHubWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema

  defmodule HealthcheckResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Healthcheck Response",
      description: "The response from the healthcheck endpoint.",
      type: :object,
      properties: %{
        status: %Schema{
          type: :string,
          description: "The operational status of the service.",
          example: "ok"
        },
        build: %Schema{
          type: :string,
          description: "The git revision of the build.",
          example: "e35ffc5"
        }
      },
      required: [:status, :build]
    })
  end

  operation(:index,
    description: "Check the health of the service.",
    summary: "Healthcheck",
    tags: ["Monitoring"],
    responses: %{200 => {"OK", "application/json", HealthcheckResponse}}
  )

  def index(conn, _params) do
    json(conn, %{status: "ok", build: System.build_info()[:revision]})
  end
end

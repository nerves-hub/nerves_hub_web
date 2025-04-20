defmodule NervesHubWeb.API.ScriptController do
  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Scripts

  plug(:validate_role, [org: :view] when action in [:index, :send])

  operation(:index,
    summary: "List all Support Scripts for a Product",
    security: [%{}, %{"bearer_auth" => []}],
    tags: ["Support Scripts"]
  )

  def index(%{assigns: %{product: product}} = conn, _params) do
    conn
    |> assign(:scripts, Scripts.all_by_product(product))
    |> render(:index)
  end

  operation(:send,
    summary: "Send a Support Script to a Device",
    security: [%{}, %{"bearer_auth" => []}],
    tags: ["Support Scripts"]
  )

  def send(%{assigns: %{device: device}} = conn, %{"id" => id}) do
    with {:ok, command} <- Scripts.get(device.product, id),
         {:ok, io} <- Scripts.Runner.send(device, command) do
      text(conn, io)
    end
  end
end

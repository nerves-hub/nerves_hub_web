defmodule NervesHubWeb.API.ScriptController do
  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Scripts

  security([%{}, %{"bearer_auth" => []}])
  tags(["Support Scripts"])

  plug(:validate_role, [org: :view] when action in [:index, :send])

  operation(:index, summary: "List all Support Scripts for a Product")

  def index(%{assigns: %{device: device}} = conn, _params) do
    conn
    |> assign(:scripts, Scripts.all_by_product(device.product))
    |> render(:index)
  end

  # This operation is defined in `NervesHubWeb.API.OpenAPI.DeviceControllerSpecs`
  operation(:send, false)

  def send(%{assigns: %{device: device}} = conn, %{"id" => id}) do
    with {:ok, command} <- Scripts.get(device.product, id),
         {:ok, io} <- Scripts.Runner.send(device, command) do
      text(conn, io)
    end
  end
end

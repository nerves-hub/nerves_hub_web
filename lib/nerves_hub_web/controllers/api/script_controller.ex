defmodule NervesHubWeb.API.ScriptController do
  use NervesHubWeb, :api_controller

  alias NervesHub.Scripts

  plug(:validate_role, [org: :view] when action in [:index, :send])

  def index(%{assigns: %{device: device}} = conn, _params) do
    conn
    |> assign(:scripts, Scripts.all_by_product(device.product))
    |> render(:index)
  end

  def send(%{assigns: %{device: device}} = conn, %{"id" => id}) do
    with {:ok, command} <- Scripts.get(device.product, id),
         {:ok, io} <- Scripts.Runner.send(device, command) do
      text(conn, io)
    end
  end
end

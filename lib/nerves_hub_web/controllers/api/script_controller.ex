defmodule NervesHubWeb.API.ScriptController do
  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Scripts

  security([%{}, %{"bearer_auth" => []}])
  tags(["Support Scripts"])

  plug(:validate_role, [org: :view] when action in [:index, :send])

  operation(:index, summary: "List all Support Scripts for a Product")

  # You can list scripts by a product or device scope:
  # /api/orgs/:org_name/products/:product_name/scripts
  # /api/orgs/:org_name/products/:product_name/devices/:device_identifier/scripts
  #
  # In the future, we'd like to just support listing by product,
  # but for now we support both.
  def index(%{assigns: %{device: device}} = conn, params), do: get_and_render_scripts(conn, device.product, params)

  def index(%{assigns: %{product: product}} = conn, params), do: get_and_render_scripts(conn, product, params)

  # This operation is defined in `NervesHubWeb.API.OpenAPI.DeviceControllerSpecs`
  operation(:send, false)

  def send(%{assigns: %{device: device}} = conn, %{"id" => id} = params) do
    with {:ok, command} <- Scripts.get(device.product, id),
         {:ok, timeout} <- get_timeout_param(params),
         {:ok, io} <- Scripts.Runner.send(device, command, timeout) do
      text(conn, io)
    else
      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> put_view(NervesHubWeb.API.ErrorJSON)
        |> render(:"500", %{reason: reason})
    end
  end

  defp get_timeout_param(%{"timeout" => timeout}) when is_integer(timeout), do: {:ok, timeout}

  defp get_timeout_param(%{"timeout" => timeout}) when is_binary(timeout) do
    case Integer.parse(timeout) do
      {value, ""} -> {:ok, value}
      _ -> {:error, "Invalid timeout value"}
    end
  end

  defp get_timeout_param(_params), do: {:ok, 30_000}

  defp get_and_render_scripts(conn, product, params) do
    filters =
      for {key, val} <- Map.get(params, "filters", %{}),
          into: %{},
          do: {String.to_existing_atom(key), val}

    opts = %{
      pagination: Map.get(params, "pagination", %{}),
      filters: filters
    }

    {scripts, page} = Scripts.filter(product, opts)

    pagination = Map.take(page, [:page_number, :page_size, :total_entries, :total_pages])

    conn
    |> assign(:scripts, scripts)
    |> assign(:pagination, pagination)
    |> render(:index)
  end
end

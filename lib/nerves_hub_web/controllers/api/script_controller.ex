defmodule NervesHubWeb.API.ScriptController do
  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Scripts
  alias NervesHubWeb.API.ErrorJSON
  alias NervesHubWeb.API.PaginationHelpers
  alias NervesHubWeb.API.Schemas.SupportScriptSchemas.SupportScriptCreationRequest
  alias NervesHubWeb.API.Schemas.SupportScriptSchemas.SupportScriptShowResponse
  alias NervesHubWeb.API.Schemas.SupportScriptSchemas.SupportScriptUpdateRequest

  security([%{}, %{"bearer_auth" => []}])
  tags(["Support Scripts"])

  plug(:validate_role, [org: :view] when action in [:index, :send])
  plug(:validate_role, [org: :manage] when action in [:create, :update, :delete])

  # OpenAPI specs for :index can be found in SupportScriptControllerSpecs

  # You can list scripts by a product or device scope:
  # /api/orgs/:org_name/products/:product_name/scripts
  # /api/devices/:device_identifier/scripts
  #
  # In the future, we'd like to just support listing by product, but for now we support both.
  def index(%{assigns: %{device: device}} = conn, params), do: get_and_render_scripts(conn, device.product, params)

  def index(%{assigns: %{current_scope: scope}} = conn, params), do: get_and_render_scripts(conn, scope.product, params)

  operation(:show,
    summary: "Get a Support Script by ID",
    parameters: [
      org_name: [
        in: :path,
        description: "Organization Name",
        type: :string,
        example: "example_org"
      ],
      product_name: [
        in: :path,
        description: "Product Name",
        type: :string,
        example: "example_product"
      ],
      script_id: [
        in: :path,
        description: "Script ID",
        type: :string,
        example: "123"
      ]
    ],
    responses: [
      ok: {"Support Scripts", "application/json", SupportScriptShowResponse}
    ]
  )

  def show(%{assigns: %{current_scope: scope}} = conn, params) do
    with {id, ""} when is_integer(id) and id > 0 <- Integer.parse(params["id"]),
         {:ok, script} <- Scripts.get(scope.product, id) do
      render(conn, :show, script: script)
    else
      _ ->
        conn
        |> put_status(:not_found)
        |> put_view(json: ErrorJSON)
        |> render(:"404")
    end
  end

  operation(:create,
    summary: "Create a Support Script",
    parameters: [
      org_name: [
        in: :path,
        description: "Organization Name",
        type: :string,
        example: "example_org"
      ],
      product_name: [
        in: :path,
        description: "Product Name",
        type: :string,
        example: "example_product"
      ]
    ],
    request_body: {
      "Support Script creation request body",
      "application/json",
      SupportScriptCreationRequest,
      required: true
    },
    responses: [
      ok: {"Support Scripts", "application/json", SupportScriptShowResponse}
    ]
  )

  def create(%{assigns: %{current_scope: scope}} = conn, params) do
    with {:ok, script} <- Scripts.create(scope.product, scope.user, params) do
      render(conn, :show, script: script)
    end
  end

  operation(:update,
    summary: "Update a Support Script",
    parameters: [
      org_name: [
        in: :path,
        description: "Organization Name",
        type: :string,
        example: "example_org"
      ],
      product_name: [
        in: :path,
        description: "Product Name",
        type: :string,
        example: "example_product"
      ],
      support_script_id: [
        in: :path,
        description: "Support Script ID",
        type: :string,
        example: "123"
      ]
    ],
    request_body: {
      "Support Script update request body",
      "application/json",
      SupportScriptUpdateRequest,
      required: true
    },
    responses: [
      ok: {"Support Scripts", "application/json", SupportScriptShowResponse}
    ]
  )

  def update(%{assigns: %{current_scope: scope}} = conn, params) do
    with {id, ""} when is_integer(id) and id > 0 <- Integer.parse(params["id"]),
         {:ok, script} <- Scripts.get(scope.product, id),
         {:ok, script} <- Scripts.update(script, scope.user, params) do
      render(conn, :show, script: script)
    end
  end

  # This operation is defined in `NervesHubWeb.API.OpenAPI.DeviceControllerSpecs`
  operation(:send, false)

  def send(%{assigns: %{device: device}} = conn, %{"name_or_id" => name_or_id} = params) do
    with {:script, {:ok, command}} <-
           {:script, Scripts.get_by_product_and_name_with_id_fallback(device.product, name_or_id)},
         {:ok, timeout} <- get_timeout_param(params),
         {:runner, {:ok, io}} <- {:runner, Scripts.Runner.send(device, command, timeout)} do
      text(conn, io)
    else
      {:script, {:error, _}} ->
        conn
        |> put_status(:not_found)
        |> put_view(json: ErrorJSON)
        |> render(:"404")

      {:runner, _} ->
        conn
        |> put_status(:forbidden)
        |> put_view(json: ErrorJSON)
        |> render(:"403", message: "device not available or responding")

      _ ->
        conn
        |> put_status(:internal_server_error)
        |> put_view(json: ErrorJSON)
        |> render(:"500")
    end
  end

  operation(:delete,
    summary: "Delete a Support Script by ID",
    parameters: [
      org_name: [
        in: :path,
        description: "Organization Name",
        type: :string,
        example: "example_org"
      ],
      product_name: [
        in: :path,
        description: "Product Name",
        type: :string,
        example: "example_product"
      ],
      script_id: [
        in: :path,
        description: "Script ID",
        type: :string,
        example: "123"
      ]
    ],
    responses: [
      no_content: "Empty response"
    ]
  )

  def delete(%{assigns: %{current_scope: scope}} = conn, params) do
    with {id, ""} when is_integer(id) and id > 0 <- Integer.parse(params["id"]),
         {:ok, _script} <- Scripts.delete(id, scope.product, scope.user) do
      send_resp(conn, :no_content, "")
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

    {scripts, page} =
      Scripts.filter(product, %{
        pagination: PaginationHelpers.atomize_pagination_params(Map.get(params, "pagination", %{})),
        filters: filters
      })

    conn
    |> assign(:scripts, scripts)
    |> assign(:pagination, PaginationHelpers.format_pagination_meta(page))
    |> render(:index)
  end
end

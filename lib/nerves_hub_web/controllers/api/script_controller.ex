defmodule NervesHubWeb.API.ScriptController do
  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Accounts.Scope
  alias NervesHub.Scripts
  alias NervesHub.Scripts.ScriptFiltering
  alias NervesHub.Types.Tag
  alias NervesHubWeb.API.ErrorJSON
  alias NervesHubWeb.API.OpenAPI.SchemaHelpers
  alias NervesHubWeb.API.PaginationHelpers
  alias NervesHubWeb.API.Plugs.RefuseDeletedDevice
  alias NervesHubWeb.API.Schemas.ErrorSchemas
  alias NervesHubWeb.API.Schemas.SupportScriptSchemas.SupportScriptCreationRequest
  alias NervesHubWeb.API.Schemas.SupportScriptSchemas.SupportScriptShowResponse
  alias NervesHubWeb.API.Schemas.SupportScriptSchemas.SupportScriptUpdateRequest

  security([%{"bearer_auth" => []}])
  tags(["Support Scripts"])

  @auth_error_responses SchemaHelpers.auth_error_responses()

  # Each filter the scripts list takes, under the name a request gives it.
  @filters Map.new(ScriptFiltering.filters(), &{Atom.to_string(&1), &1})

  plug(:require_membership when action in [:index, :show])
  plug(:require_permission, :"support_script:run" when action in [:send])
  plug(:require_permission, :"support_script:create" when action in [:create])
  plug(:require_permission, :"support_script:update" when action in [:update])
  plug(:require_permission, :"support_script:delete" when action in [:delete])

  plug(RefuseDeletedDevice when action in [:send])

  # OpenAPI specs for :index can be found in SupportScriptControllerSpecs
  operation(:index, [])

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
      id: [
        in: :path,
        description: "Script ID",
        type: :string,
        example: "123"
      ]
    ],
    responses:
      [
        ok: {"Support Scripts", "application/json", SupportScriptShowResponse},
        not_found: {"Not Found", "application/json", ErrorSchemas.ErrorResponse}
      ] ++ @auth_error_responses
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
    responses:
      [
        # The script is created, but the response is a 200 rather than a 201.
        ok: {"Support Scripts", "application/json", SupportScriptShowResponse},
        unprocessable_entity: {"Unprocessable Entity", "application/json", ErrorSchemas.ChangesetErrorResponse}
      ] ++ @auth_error_responses
  )

  def create(%{assigns: %{current_scope: scope}} = conn, params) do
    with {:ok, script} <- Scripts.create(scope.product, Scope.actor(scope), params) do
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
      id: [
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
    responses:
      [
        ok: {"Support Scripts", "application/json", SupportScriptShowResponse},
        not_found: {"Not Found", "application/json", ErrorSchemas.ErrorResponse},
        unprocessable_entity: {"Unprocessable Entity", "application/json", ErrorSchemas.ChangesetErrorResponse}
      ] ++ @auth_error_responses
  )

  def update(%{assigns: %{current_scope: scope}} = conn, params) do
    with {id, ""} when is_integer(id) and id > 0 <- Integer.parse(params["id"]),
         {:ok, script} <- Scripts.get(scope.product, id),
         {:ok, script} <- Scripts.update(script, Scope.actor(scope), params) do
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
      id: [
        in: :path,
        description: "Script ID",
        type: :string,
        example: "123"
      ]
    ],
    responses:
      [
        no_content: "Empty response",
        not_found: {"Not Found", "application/json", ErrorSchemas.ErrorResponse}
      ] ++ @auth_error_responses
  )

  def delete(%{assigns: %{current_scope: scope}} = conn, params) do
    with {id, ""} when is_integer(id) and id > 0 <- Integer.parse(params["id"]),
         {:ok, _script} <- Scripts.delete(id, scope.product, Scope.actor(scope)) do
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
    with {:ok, filters} <- cast_filters(params["filters"]),
         {:ok, pagination} <- PaginationHelpers.cast_pagination_params(params["pagination"]) do
      {scripts, page} = Scripts.filter(product, %{pagination: pagination, filters: filters})

      conn
      |> assign(:scripts, scripts)
      |> assign(:pagination, PaginationHelpers.format_pagination_meta(page))
      |> render(:index)
    end
  end

  # A key that isn't a filter, or a value its filter can't take, is a 422
  # rather than dropped. A dropped filter lists scripts it was meant to leave
  # out.
  defp cast_filters(nil), do: {:ok, %{}}

  defp cast_filters(filters) when is_map(filters) do
    Enum.reduce_while(filters, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case cast_filter(Map.fetch(@filters, key), value) do
        {:ok, filter} -> {:cont, {:ok, Map.put(acc, filter, value)}}
        {:error, message} -> {:halt, {:error, {:invalid_query_param, "filters[#{key}] #{message}."}}}
      end
    end)
  end

  defp cast_filters(filters) do
    {:error,
     {:invalid_query_param, "filters must be an object, such as filters[search]=cleanup, got #{inspect(filters)}."}}
  end

  defp cast_filter(:error, _value) do
    {:error, "is not a support script filter. The filters are #{Enum.join(ScriptFiltering.filters(), ", ")}"}
  end

  defp cast_filter({:ok, :tags}, value) when is_binary(value) do
    case Tag.cast(value) do
      {:ok, _tags} -> {:ok, :tags}
      {:error, message: message} -> {:error, "#{message}, got #{inspect(value)}"}
    end
  end

  defp cast_filter({:ok, filter}, value) when is_binary(value), do: {:ok, filter}
  defp cast_filter({:ok, _filter}, value), do: {:error, "must be a string, got #{inspect(value)}"}
end

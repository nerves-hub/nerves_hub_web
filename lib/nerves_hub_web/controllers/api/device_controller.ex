defmodule NervesHubWeb.API.DeviceController do
  use NervesHubWeb, :api_controller

  alias NervesHub.Accounts
  alias NervesHub.Consoles
  alias NervesHub.DeviceEvents
  alias NervesHub.Devices
  alias NervesHub.Devices.AdvancedQuery
  alias NervesHub.Devices.BulkActions
  alias NervesHub.Devices.Certificates
  alias NervesHub.Devices.DeviceCertificate
  alias NervesHub.Devices.Updates
  alias NervesHub.Firmwares
  alias NervesHub.Products
  alias NervesHubWeb.API.PaginationHelpers
  alias NervesHubWeb.Endpoint
  alias NervesHubWeb.Helpers.Authorization

  require Logger

  plug(:require_membership when action in [:index, :show, :auth])
  plug(:require_permission, :"device:create" when action in [:create, :bulk_import])
  plug(:require_permission, :"device:update" when action in [:update, :move])
  plug(:require_permission, :"device:delete" when action in [:delete])
  plug(:require_permission, :"device:reboot" when action in [:reboot])
  plug(:require_permission, :"device:reconnect" when action in [:reconnect])
  plug(:require_permission, :"device:push-update" when action in [:upgrade])
  plug(:require_permission, :"device:clear-penalty-box" when action in [:penalty])
  # Sends keystrokes to the device's console, as someone at the console would.
  plug(:require_permission, :"device:console" when action in [:code])

  def index(%{assigns: %{current_scope: %{org: org}, product: product}} = conn, params) do
    filters = Map.get(params, "filters", %{}) |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)

    with :ok <- validate_advanced_query(filters, product.id) do
      list_devices(conn, org, product, params, filters)
    end
  end

  defp list_devices(conn, org, product, params, filters) do
    opts = %{
      pagination: PaginationHelpers.atomize_pagination_params(Map.get(params, "pagination", %{})),
      filters: filters
    }

    opts =
      if sort_field = Map.get(params, "sort") do
        Map.put(opts, :sort, {sort_direction(params), String.to_existing_atom(sort_field)})
      else
        opts
      end

    {devices, page} =
      Devices.get_devices_by_org_id_and_product_id_with_pager(org.id, product.id, opts)

    conn
    |> assign(:devices, devices)
    |> assign(:pagination, PaginationHelpers.format_pagination_meta(page))
    |> render(:index)
  end

  # An invalid advanced query is a 422 with the parse error, rather than the
  # UI's silent "apply nothing" behavior - API callers should hear about typos.
  # Free-text input (anything that doesn't look like a query expression) is
  # still accepted and searched as text, the same as the UI search box.
  defp validate_advanced_query(%{advanced_query: query}, product_id) when is_binary(query) do
    case String.trim(query) == "" || AdvancedQuery.interpret(query, product_id) do
      true ->
        :ok

      {:ok, _canonical_query, _ast} ->
        :ok

      {:error, message, position} ->
        {:error, {:advanced_query, "invalid advanced query: #{message} (at character #{position})"}}
    end
  end

  defp validate_advanced_query(_filters, _product_id), do: :ok

  def create(%{assigns: %{current_scope: %{org: org}, product: product}} = conn, params) do
    params =
      params
      |> Map.put("org_id", org.id)
      |> Map.put("product_id", product.id)

    with {:ok, device} <- Devices.create_device(params) do
      device = Devices.get_by_identifier_with_deployment_and_release!(device.identifier)

      conn
      |> put_status(:created)
      |> put_resp_header(
        "location",
        Routes.api_device_path(conn, :show, org.name, product.name, device.identifier)
      )
      |> render(:show, device: device)
    end
  end

  def bulk_import(%{assigns: %{current_scope: %{org: org}, product: product}} = conn, import_list) do
    format = get_req_header(conn, "format") |> List.first()
    tags = get_req_header(conn, "tags") |> List.first()

    with {:ok, _task_pid} <-
           BulkActions.async_bulk_create(
             org.id,
             product.id,
             import_list["_json"],
             format || "microchip_trust_and_go",
             tags
           ) do
      send_resp(conn, 201, "")
    end
  end

  def show(conn, _) do
    render(conn, :show)
  end

  def delete(%{assigns: %{device: device}} = conn, _params) do
    {:ok, _device} = Devices.delete_device(device)

    send_resp(conn, :no_content, "")
  end

  def update(%{assigns: %{device: device}} = conn, params) do
    with {:ok, updated_device} <- Devices.update_device(device, params) do
      updated_device = Devices.get_by_identifier_with_deployment_and_release!(updated_device.identifier)

      conn
      |> put_status(201)
      |> render(:show, device: updated_device)
    end
  end

  def auth(%{assigns: %{current_scope: %{org: org}}} = conn, %{"certificate" => cert64}) do
    with {:ok, cert_pem} <- Base.decode64(cert64),
         {:ok, cert} <- X509.Certificate.from_pem(cert_pem),
         {:ok, %DeviceCertificate{device_id: device_id}} <-
           Certificates.get_device_certificate_by_x509(cert),
         {:ok, device} <- Devices.get_device_by_org(org, device_id) do
      device = Devices.get_by_identifier_with_deployment_and_release!(device.identifier)

      conn
      |> put_status(200)
      |> render(:show, device: device)
    else
      _e ->
        conn
        |> send_resp(403, Jason.encode!(%{status: "Unauthorized"}))
    end
  end

  def reboot(%{assigns: %{current_scope: %{user: user}, device: device}} = conn, _params) do
    DeviceEvents.reboot(device, user)

    send_resp(conn, :no_content, "")
  end

  def reconnect(%{assigns: %{device: device}} = conn, _params) do
    _ = Endpoint.broadcast("device_socket:#{device.id}", "disconnect", %{})

    send_resp(conn, :no_content, "")
  end

  def code(%{assigns: %{device: device}} = conn, params)
      when is_map_key(params, "code")
      when is_map_key(params, "body") do
    code = params["code"] || params["body"]

    code
    |> String.graphemes()
    |> Enum.each(fn character ->
      Consoles.PubSub.broadcast_to_console(device.id, "dn", %{"data" => character})
    end)

    Consoles.PubSub.broadcast_to_console(device.id, "dn", %{"data" => "\r"})

    send_resp(conn, :no_content, "")
  end

  def code(_conn, _params) do
    raise NervesHubWeb.InvalidRequestError, info: "code or body parameter required"
  end

  def upgrade(%{assigns: %{device: device, current_scope: scope}} = conn, %{"uuid" => uuid}) do
    # Firmware that has been deleted no longer resolves here, which is the point
    # — its file is gone, and a device told to fetch it would fail the update.
    with {:ok, firmware} <- Firmwares.get_firmware_by_product_and_uuid(device.product, uuid) do
      Logger.info("Manually sending full firmware",
        firmware_uuid: firmware.uuid,
        device_identifier: device.identifier
      )

      opts =
        if proxy_url = get_in(scope.org.settings.firmware_proxy_url) do
          [firmware_proxy_url: proxy_url]
        else
          []
        end

      {:ok, _device} = DeviceEvents.manual_update(device, firmware, scope.user, opts)

      send_resp(conn, :no_content, "")
    end
  end

  def penalty(%{assigns: %{device: device, current_scope: %{user: user}}} = conn, _params) do
    case Updates.clear_penalty_box(device, user) do
      {:ok, _device} ->
        send_resp(conn, :no_content, "")

      {:error, _, _, _} ->
        {:error, "Failed to clear penalty box. Please contact support if this persists."}
    end
  end

  def move(%{assigns: %{device: device, current_scope: %{user: user}}} = conn, %{
        "new_org_name" => org_name,
        "new_product_name" => product_name
      }) do
    with {:ok, move_to_org} <- Accounts.get_org_by_name(org_name),
         :ok <- authorize_move_into!(move_to_org, user),
         {:ok, product} <- Products.get_product_by_org_id_and_name(move_to_org.id, product_name) do
      case Devices.move(device, product, user) do
        {:ok, device} ->
          device = Devices.get_by_identifier_with_deployment_and_release!(device.identifier)

          conn
          |> assign(:device, device)
          |> render(:show)

        # `Devices.move/3` runs a Multi, so a failed step, such as updating a
        # deleted device, comes back as a 4-tuple. The fallback controller
        # renders the changeset.
        {:error, _step, changeset, _changes} ->
          {:error, changeset}
      end
    end
  end

  # `sort_direction` arrives as a raw query param — the OpenAPI spec types it as
  # a free-form string and nothing casts it before we get here. Running it
  # through `String.to_atom/1` minted a permanent atom per distinct value, so
  # anyone with `org: :view` could grow the atom table until the node hit the
  # limit and aborted. Only two directions mean anything; everything else is
  # the default.
  defp sort_direction(params) do
    case Map.get(params, "sort_direction") do
      "desc" -> :desc
      _ -> :asc
    end
  end

  # Moving a device into another org adds a device there, so the user has to be
  # able to add devices in that org too.
  defp authorize_move_into!(org, user) do
    case Accounts.get_org_user(org, user) do
      {:ok, org_user} -> Authorization.authorized!(:"device:create", org_user)
      {:error, :not_found} -> raise NervesHubWeb.UnauthorizedError
    end

    :ok
  end
end

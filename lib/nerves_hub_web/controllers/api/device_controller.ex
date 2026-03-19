defmodule NervesHubWeb.API.DeviceController do
  use NervesHubWeb, :api_controller

  import Ecto.Query

  alias NervesHub.Accounts
  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.DeviceEvents
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceCertificate
  alias NervesHub.Devices.UpdatePayload
  alias NervesHub.Firmwares
  alias NervesHub.Products
  alias NervesHub.Repo
  alias NervesHubWeb.API.PaginationHelpers
  alias NervesHubWeb.Endpoint
  alias NervesHubWeb.Helpers.RoleValidateHelpers

  plug(
    :validate_role,
    [org: :manage]
    when action in [
           :create,
           :update,
           :delete,
           :reboot,
           :reconnect,
           :upgrade,
           :penalty,
           :move,
           :code
         ]
  )

  plug(:validate_role, [org: :view] when action in [:index, :show, :auth])

  def index(%{assigns: %{current_scope: %{org: org}, product: product}} = conn, params) do
    opts = %{
      pagination: PaginationHelpers.atomize_pagination_params(Map.get(params, "pagination", %{})),
      filters: Map.get(params, "filters", %{})
    }

    {devices, page} =
      Devices.get_devices_by_org_id_and_product_id_with_pager(org.id, product.id, opts)

    conn
    |> assign(:devices, devices)
    |> assign(:pagination, PaginationHelpers.format_pagination_meta(page))
    |> render(:index)
  end

  def create(%{assigns: %{current_scope: %{org: org}, product: product}} = conn, params) do
    params =
      params
      |> Map.put("org_id", org.id)
      |> Map.put("product_id", product.id)

    with {:ok, device} <- Devices.create_device(params) do
      device = preload_device(device)

      conn
      |> put_status(:created)
      |> put_resp_header(
        "location",
        Routes.api_device_path(conn, :show, org.name, product.name, device.identifier)
      )
      |> render(:show, device: device)
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
      updated_device = preload_device(updated_device)

      conn
      |> put_status(201)
      |> render(:show, device: updated_device)
    end
  end

  def auth(%{assigns: %{current_scope: %{org: org}}} = conn, %{"certificate" => cert64}) do
    with {:ok, cert_pem} <- Base.decode64(cert64),
         {:ok, cert} <- X509.Certificate.from_pem(cert_pem),
         {:ok, %DeviceCertificate{device_id: device_id}} <-
           Devices.get_device_certificate_by_x509(cert),
         {:ok, device} <- Devices.get_device_by_org(org, device_id) do
      device = preload_device(device)

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
      Endpoint.broadcast_from!(self(), "device:console:#{device.id}", "dn", %{
        "data" => character
      })
    end)

    Endpoint.broadcast_from!(self(), "device:console:#{device.id}", "dn", %{"data" => "\r"})

    send_resp(conn, :no_content, "")
  end

  def code(_conn, _params) do
    raise NervesHubWeb.InvalidRequestError, info: "code or body parameter required"
  end

  def upgrade(%{assigns: %{device: device, current_scope: %{user: user}}} = conn, %{"uuid" => uuid}) do
    {:ok, firmware} = Firmwares.get_firmware_by_product_and_uuid(device.product, uuid)

    {:ok, url} = Firmwares.get_firmware_url(firmware)
    {:ok, meta} = Firmwares.metadata_from_firmware(firmware)

    {:ok, device} = Devices.disable_updates(device, user)
    device = Repo.preload(device, [:device_certificates])

    DeviceTemplates.audit_firmware_pushed(user, device, firmware)

    payload = %UpdatePayload{
      update_available: true,
      firmware_url: url,
      firmware_meta: meta
    }

    _ =
      NervesHubWeb.Endpoint.broadcast(
        "device:#{device.id}",
        "deployments/update",
        payload
      )

    send_resp(conn, :no_content, "")
  end

  def penalty(%{assigns: %{device: device, current_scope: %{user: user}}} = conn, _params) do
    case Devices.clear_penalty_box(device, user) do
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
         RoleValidateHelpers.validate_org_user_role(conn, move_to_org, user, :manage),
         {:ok, product} <- Products.get_product_by_org_id_and_name(move_to_org.id, product_name) do
      case Devices.move(device, product, user) do
        {:ok, device} ->
          device = preload_device(device)

          conn
          |> assign(:device, device)
          |> render(:show)

        {:error, changeset} ->
          # fallback controller will render this
          {:error, changeset}
      end
    end
  end

  defp preload_device(%{identifier: identifier}) do
    Device
    |> where(identifier: ^identifier)
    |> Devices.join_and_preload_deployment_group_and_current_release()
    |> preload([:org, :product, :latest_connection])
    |> Repo.one!()
  end
end

defmodule NervesHubWeb.API.DeviceController do
  use NervesHubWeb, :api_controller

  alias NervesHub.Accounts
  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.DeviceEvents
  alias NervesHub.Devices
  alias NervesHub.Devices.DeviceCertificate
  alias NervesHub.Devices.UpdatePayload
  alias NervesHub.Firmwares
  alias NervesHub.Products
  alias NervesHub.Repo
  alias NervesHubWeb.API.PaginationHelpers
  alias NervesHubWeb.Endpoint
  alias NervesHubWeb.Helpers.RoleValidateHelpers
  alias Phoenix.Socket.Broadcast

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

  def index(%{assigns: %{org: org, product: product}} = conn, params) do
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

  def create(%{assigns: %{org: org, product: product}} = conn, params) do
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

  def delete(%{assigns: %{org: _org, device: device}} = conn, _params) do
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

  def auth(%{assigns: %{org: org}} = conn, %{"certificate" => cert64}) do
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

  def reboot(%{assigns: %{user: user, device: device}} = conn, _params) do
    DeviceEvents.reboot(device, user)

    send_resp(conn, :no_content, "")
  end

  def reconnect(%{assigns: %{device: device}} = conn, _params) do
    _ = Endpoint.broadcast("device_socket:#{device.id}", "disconnect", %{})

    send_resp(conn, :no_content, "")
  end

  def code(%{assigns: %{device: device}} = conn, %{"body" => body, "stream" => true}) do
    # Subscribe to console output before sending code
    _ = Endpoint.subscribe("user:console:#{device.id}")

    # Send the code to the device
    send_code_to_device(device, body)

    # Stream the response back
    conn
    |> put_resp_content_type("text/plain")
    |> send_chunked(200)
    |> stream_console_output()
  end

  def code(%{assigns: %{device: device}} = conn, %{"body" => body}) do
    send_code_to_device(device, body)
    send_resp(conn, :no_content, "")
  end

  defp send_code_to_device(device, body) do
    body
    |> String.graphemes()
    |> Enum.each(fn character ->
      Endpoint.broadcast_from!(self(), "device:console:#{device.id}", "dn", %{
        "data" => character
      })
    end)

    Endpoint.broadcast_from!(self(), "device:console:#{device.id}", "dn", %{"data" => "\r"})
  end

  defp stream_console_output(conn) do
    receive do
      %Broadcast{event: "up", payload: %{"data" => data}} ->
        case chunk(conn, data) do
          {:ok, conn} -> stream_console_output(conn)
          {:error, :closed} -> conn
        end

      %Broadcast{event: _other} ->
        # Ignore other events (file-data, etc.)
        stream_console_output(conn)
    after
      10_000 ->
        # Send keepalive empty chunk every 10 seconds
        case chunk(conn, "") do
          {:ok, conn} -> stream_console_output(conn)
          {:error, :closed} -> conn
        end
    end
  end

  def upgrade(%{assigns: %{device: device, user: user}} = conn, %{"uuid" => uuid}) do
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

  def penalty(%{assigns: %{device: device, user: user}} = conn, _params) do
    case Devices.clear_penalty_box(device, user) do
      {:ok, _device} ->
        send_resp(conn, :no_content, "")

      {:error, _, _, _} ->
        {:error, "Failed to clear penalty box. Please contact support if this persists."}
    end
  end

  def move(%{assigns: %{device: device, user: user}} = conn, %{
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

  defp preload_device(device) do
    Repo.preload(device, [
      :org,
      :product,
      :latest_connection,
      deployment_group: [:firmware]
    ])
  end
end

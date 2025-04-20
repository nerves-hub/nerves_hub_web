defmodule NervesHubWeb.API.DeviceController do
  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Accounts
  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.Devices
  alias NervesHub.Devices.DeviceCertificate
  alias NervesHub.Devices.UpdatePayload
  alias NervesHub.Firmwares
  alias NervesHub.Products
  alias NervesHub.Repo

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

  operation(:index,
    summary: "List all Devices for a Product",
    security: [%{}, %{"bearer_auth" => []}],
    tags: ["Devices"]
  )

  def index(%{assigns: %{org: org, product: product}} = conn, params) do
    opts = %{
      pagination: Map.get(params, "pagination", %{}),
      filters: Map.get(params, "filters", %{})
    }

    {devices, page} =
      Devices.get_devices_by_org_id_and_product_id_with_pager(org.id, product.id, opts)

    pagination = Map.take(page, [:page_number, :page_size, :total_entries, :total_pages])

    conn
    |> assign(:devices, devices)
    |> assign(:pagination, pagination)
    |> render(:index)
  end

  operation(:create,
    summary: "Create a Device for a Product",
    security: [%{}, %{"bearer_auth" => []}],
    tags: ["Devices"]
  )

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

  operation(:show,
    summary: "Show a Device for a Product",
    security: [%{}, %{"bearer_auth" => []}],
    tags: ["Devices"]
  )

  def show(conn, _) do
    render(conn, :show)
  end

  operation(:delete,
    summary: "Delete a Device for a Product",
    security: [%{}, %{"bearer_auth" => []}],
    tags: ["Devices"]
  )

  def delete(%{assigns: %{org: _org, device: device}} = conn, _params) do
    {:ok, _device} = Devices.delete_device(device)

    send_resp(conn, :no_content, "")
  end

  operation(:update,
    summary: "Update a Device for a Product",
    security: [%{}, %{"bearer_auth" => []}],
    tags: ["Devices"]
  )

  def update(%{assigns: %{device: device}} = conn, params) do
    with {:ok, updated_device} <- Devices.update_device(device, params) do
      updated_device = preload_device(updated_device)

      conn
      |> put_status(201)
      |> render(:show, device: updated_device)
    end
  end

  operation(:auth,
    summary: "Test a Devices Certificate authentication",
    security: [%{}, %{"bearer_auth" => []}],
    tags: ["Devices"]
  )

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

  operation(:reboot,
    summary: "Request a Device reboot",
    security: [%{}, %{"bearer_auth" => []}],
    tags: ["Devices"]
  )

  def reboot(%{assigns: %{user: user, device: device}} = conn, _params) do
    DeviceTemplates.audit_reboot(user, device)

    _ = Endpoint.broadcast_from(self(), "device:#{device.id}", "reboot", %{})

    send_resp(conn, 200, "Success")
  end

  operation(:reconnect,
    summary: "Request a Device reconnect",
    security: [%{}, %{"bearer_auth" => []}],
    tags: ["Devices"]
  )

  def reconnect(%{assigns: %{device: device}} = conn, _params) do
    _ = Endpoint.broadcast("device_socket:#{device.id}", "disconnect", %{})

    send_resp(conn, 200, "Success")
  end

  operation(:code,
    summary: "Request a Device run some Elixir code in it's console connection",
    security: [%{}, %{"bearer_auth" => []}],
    tags: ["Devices"]
  )

  def code(%{assigns: %{device: device}} = conn, %{"body" => body}) do
    body
    |> String.graphemes()
    |> Enum.each(fn character ->
      Endpoint.broadcast_from!(self(), "device:console:#{device.id}", "dn", %{
        "data" => character
      })
    end)

    Endpoint.broadcast_from!(self(), "device:console:#{device.id}", "dn", %{"data" => "\r"})

    send_resp(conn, 200, "Success")
  end

  operation(:upgrade,
    summary: "Send new Firmware to a Device",
    security: [%{}, %{"bearer_auth" => []}],
    tags: ["Devices"]
  )

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

    send_resp(conn, 204, "")
  end

  operation(:penalty,
    summary: "Clear the penalty box for a Device",
    security: [%{}, %{"bearer_auth" => []}],
    tags: ["Devices"]
  )

  def penalty(%{assigns: %{device: device, user: user}} = conn, _params) do
    case Devices.clear_penalty_box(device, user) do
      {:ok, _device} ->
        send_resp(conn, 204, "")

      {:error, _, _, _} ->
        {:error, "Failed to clear penalty box. Please contact support if this persists."}
    end
  end

  operation(:move,
    summary: "Move a Device to a different Product in the same or different Organization",
    security: [%{}, %{"bearer_auth" => []}],
    tags: ["Devices"]
  )

  def move(%{assigns: %{device: device, user: user}} = conn, %{
        "new_org_name" => org_name,
        "new_product_name" => product_name
      }) do
    with {:ok, move_to_org} <- Accounts.get_org_by_name(org_name),
         _ <- RoleValidateHelpers.validate_org_user_role(conn, move_to_org, user, :manage),
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

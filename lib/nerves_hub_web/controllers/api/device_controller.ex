defmodule NervesHubWeb.API.DeviceController do
  use NervesHubWeb, :api_controller

  alias NervesHub.Accounts
  alias NervesHub.AuditLogs
  alias NervesHub.Devices
  alias NervesHub.Devices.DeviceCertificate
  alias NervesHub.Devices.UpdatePayload
  alias NervesHub.Firmwares
  alias NervesHub.Repo
  alias NervesHubWeb.Endpoint

  action_fallback(NervesHubWeb.API.FallbackController)

  plug(:validate_role, [org: :delete] when action in [:delete])
  plug(:validate_role, [org: :write] when action in [:create, :update])
  plug(:validate_role, [org: :read] when action in [:index, :auth])

  def index(%{assigns: %{org: org, product: product}} = conn, params) do
    opts = %{
      pagination: Map.get(params, "pagination", %{}),
      filters: Map.get(params, "filters", %{})
    }

    page = Devices.get_devices_by_org_id_and_product_id(org.id, product.id, opts)
    pagination = Map.take(page, [:page_number, :page_size, :total_entries, :total_pages])

    conn
    |> assign(:devices, page.entries)
    |> assign(:pagination, pagination)
    |> render("index.json")
  end

  def create(%{assigns: %{org: org, product: product}} = conn, params) do
    params =
      params
      |> Map.put("org_id", org.id)
      |> Map.put("product_id", product.id)

    with {:ok, device} <- Devices.create_device(params) do
      conn
      |> put_status(:created)
      |> put_resp_header(
        "location",
        Routes.device_path(conn, :show, org.name, product.name, device.identifier)
      )
      |> render("show.json", device: device)
    end
  end

  def show(conn, %{"identifier" => identifier}) do
    %{user: user} = conn.assigns

    case Devices.get_by_identifier(identifier) do
      {:ok, device} ->
        if Accounts.has_org_role?(device.org, user, :read) do
          conn
          |> assign(:device, device)
          |> render("show.json")
        else
          conn
          |> put_resp_header("content-type", "application/json")
          |> send_resp(403, Jason.encode!(%{status: "missing required role: read"}))
        end

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> put_view(NervesHubWeb.API.ErrorView)
        |> render(:"404")
    end
  end

  def delete(%{assigns: %{org: org}} = conn, %{"identifier" => identifier}) do
    {:ok, device} = Devices.get_device_by_identifier(org, identifier)
    {:ok, _device} = Devices.delete_device(device)

    send_resp(conn, :no_content, "")
  end

  def update(%{assigns: %{org: org}} = conn, %{"identifier" => identifier} = params) do
    with {:ok, device} <- Devices.get_device_by_identifier(org, identifier),
         {:ok, updated_device} <- Devices.update_device(device, params) do
      conn
      |> put_status(201)
      |> render("show.json", device: updated_device)
    end
  end

  def auth(%{assigns: %{org: org}} = conn, %{"certificate" => cert64}) do
    with {:ok, cert_pem} <- Base.decode64(cert64),
         {:ok, cert} <- X509.Certificate.from_pem(cert_pem),
         {:ok, %DeviceCertificate{device_id: device_id}} <-
           Devices.get_device_certificate_by_x509(cert),
         {:ok, device} <- Devices.get_device_by_org(org, device_id) do
      conn
      |> put_status(200)
      |> render("show.json", device: device)
    else
      _e ->
        conn
        |> send_resp(403, Jason.encode!(%{status: "Unauthorized"}))
    end
  end

  def reboot(conn, %{"identifier" => identifier}) do
    %{user: user} = conn.assigns

    case Devices.get_by_identifier(identifier) do
      {:ok, device} ->
        if Accounts.has_org_role?(device.org, user, :write) do
          message = "user #{user.username} rebooted device #{device.identifier}"
          AuditLogs.audit!(user, device, message)

          Endpoint.broadcast_from(self(), "device:#{device.id}", "reboot", %{})

          send_resp(conn, 200, "Success")
        else
          conn
          |> put_resp_header("content-type", "application/json")
          |> send_resp(403, Jason.encode!(%{status: "missing required role: write"}))
        end

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> put_view(NervesHubWeb.API.ErrorView)
        |> render(:"404")
    end
  end

  def reconnect(conn, %{"identifier" => identifier}) do
    %{user: user} = conn.assigns

    case Devices.get_by_identifier(identifier) do
      {:ok, device} ->
        if Accounts.has_org_role?(device.org, user, :write) do
          Endpoint.broadcast("device_socket:#{device.id}", "disconnect", %{})

          send_resp(conn, 200, "Success")
        else
          conn
          |> put_resp_header("content-type", "application/json")
          |> send_resp(403, Jason.encode!(%{status: "missing required role: write"}))
        end

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> put_view(NervesHubWeb.API.ErrorView)
        |> render(:"404")
    end
  end

  def code(conn, %{"identifier" => identifier, "body" => body}) do
    %{user: user} = conn.assigns

    case Devices.get_by_identifier(identifier) do
      {:ok, device} ->
        if Accounts.has_org_role?(device.org, user, :write) do
          body
          |> String.graphemes()
          |> Enum.map(fn character ->
            Endpoint.broadcast_from!(self(), "console:#{device.id}", "dn", %{"data" => character})
          end)

          Endpoint.broadcast_from!(self(), "console:#{device.id}", "dn", %{"data" => "\r"})

          send_resp(conn, 200, "Success")
        else
          conn
          |> put_resp_header("content-type", "application/json")
          |> send_resp(403, Jason.encode!(%{status: "missing required role: write"}))
        end

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> put_view(NervesHubWeb.API.ErrorView)
        |> render(:"404")
    end
  end

  def upgrade(conn, %{"identifier" => identifier, "uuid" => uuid}) do
    %{user: user} = conn.assigns

    case Devices.get_by_identifier(identifier) do
      {:ok, device} ->
        if Accounts.has_org_role?(device.org, user, :write) do
          {:ok, firmware} = Firmwares.get_firmware_by_product_and_uuid(device.product, uuid)

          {:ok, url} = Firmwares.get_firmware_url(firmware)
          {:ok, meta} = Firmwares.metadata_from_firmware(firmware)

          {:ok, device} = Devices.disable_updates(device, user)
          device = Repo.preload(device, [:device_certificates])

          description =
            "user #{user.username} pushed firmware #{firmware.version} #{firmware.uuid} to device #{device.identifier}"

          AuditLogs.audit!(user, device, description)

          payload = %UpdatePayload{
            update_available: true,
            firmware_url: url,
            firmware_meta: meta
          }

          NervesHubWeb.Endpoint.broadcast(
            "device:#{device.id}",
            "deployments/update",
            payload
          )

          send_resp(conn, 204, "")
        else
          conn
          |> put_resp_header("content-type", "application/json")
          |> send_resp(403, Jason.encode!(%{status: "missing required role: write"}))
        end

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> put_view(NervesHubWeb.API.ErrorView)
        |> render(:"404")
    end
  end

  def penalty(conn, %{"identifier" => identifier}) do
    %{user: user} = conn.assigns

    case Devices.get_by_identifier(identifier) do
      {:ok, device} ->
        if Accounts.has_org_role?(device.org, user, :write) do
          case Devices.clear_penalty_box(device, user) do
            {:ok, _device} ->
              send_resp(conn, 204, "")

            {:error, _changeset} ->
              send_resp(conn, 400, "")
          end
        else
          conn
          |> put_resp_header("content-type", "application/json")
          |> send_resp(403, Jason.encode!(%{status: "missing required role: write"}))
        end

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> put_view(NervesHubWeb.API.ErrorView)
        |> render(:"404")
    end
  end
end

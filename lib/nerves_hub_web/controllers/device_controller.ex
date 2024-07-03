defmodule NervesHubWeb.DeviceController do
  use NervesHubWeb, :controller

  alias NervesHub.AuditLogs
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHubWeb.DeviceLive
  alias NervesHubWeb.Endpoint

  plug(
    :validate_role,
    [org: :manage] when action in [:new, :create, :edit, :delete, :reboot, :toggle_updates]
  )

  plug(
    :validate_role,
    [org: :view]
    when action in [:index, :console, :show, :download_certificate, :export_audit_logs]
  )

  def index(%{assigns: %{user: user, org: org, product: product}} = conn, _params) do
    conn
    |> live_render(
      DeviceLive.Index,
      session: %{
        "auth_user_id" => user.id,
        "org_id" => org.id,
        "product_id" => product.id
      }
    )
  end

  def new(%{assigns: %{org: _org}} = conn, _params) do
    conn
    |> assign(:changeset, Ecto.Changeset.change(%Device{}))
    |> render("new.html")
  end

  def create(%{assigns: %{org: org, product: product}} = conn, %{"device" => params}) do
    params
    |> Map.put("org_id", org.id)
    |> Map.put("product_id", product.id)
    |> Devices.create_device()
    |> case do
      {:ok, device} ->
        conn
        |> redirect(
          to: Routes.device_path(conn, :show, org.name, product.name, device.identifier)
        )

      {:error, changeset} ->
        conn
        |> put_flash(:error, "Failed to add device.")
        |> render("new.html", changeset: changeset)
    end
  end

  def show(%{assigns: %{user: user, org: org, product: product, device: device}} = conn, _params) do
    conn
    |> live_render(
      DeviceLive.Show,
      session: %{
        "auth_user_id" => user.id,
        "org_id" => org.id,
        "product_id" => product.id,
        "device_id" => device.id
      }
    )
  end

  def edit(conn, _params) do
    %{device: device} = conn.assigns

    conn
    |> assign(:changeset, Ecto.Changeset.change(device, %{}))
    |> render("edit.html")
  end

  def update(conn, %{"device" => params}) do
    %{user: user, org: org, product: product, device: device} = conn.assigns

    message = "#{user.name} updated device #{device.identifier}"

    case Devices.update_device_with_audit(device, params, user, message) do
      {:ok, device} ->
        conn
        |> put_flash(:info, "Device updated")
        |> redirect(
          to: Routes.device_path(conn, :show, org.name, product.name, device.identifier)
        )

      {:error, changeset} ->
        conn
        |> assign(:changeset, changeset)
        |> render("edit.html")
    end
  end

  def delete(%{assigns: %{org: org, product: product, device: device}} = conn, _params) do
    {:ok, _device} = Devices.delete_device(device)

    conn
    |> put_flash(:info, "Device deleted successfully.")
    |> redirect(to: Routes.device_path(conn, :index, org.name, product.name))
  end

  def reboot(conn, _params) do
    %{user: user, org: org, product: product, device: device} = conn.assigns

    AuditLogs.audit!(user, device, "#{user.name} rebooted device #{device.identifier}")

    Endpoint.broadcast_from!(self(), "device:#{device.id}", "reboot", %{})

    conn
    |> put_flash(:info, "Device Reboot Requested")
    |> redirect(to: Routes.device_path(conn, :index, org.name, product.name))
  end

  def toggle_updates(conn, _params) do
    %{user: user, org: org, product: product, device: device} = conn.assigns

    case Devices.toggle_health(device, user) do
      {:ok, _device} ->
        conn
        |> put_flash(:info, "Toggled device firmware updates")
        |> redirect(to: Routes.device_path(conn, :index, org.name, product.name))

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to toggle device firmware updates")
        |> redirect(to: Routes.device_path(conn, :index, org.name, product.name))
    end
  end

  def console(conn, _params) do
    conn
    |> put_root_layout({NervesHubWeb.LayoutView, :console})
    |> put_layout(false)
    |> render("console.html")
  end

  def download_certificate(%{assigns: %{device: device}} = conn, %{"cert_serial" => serial}) do
    case Enum.find(device.device_certificates, &(&1.serial == serial)) do
      %{der: der} ->
        filename = "#{device.identifier}-cert.pem"
        pem = X509.Certificate.from_der!(der) |> X509.Certificate.to_pem()
        send_download(conn, {:binary, pem}, filename: filename)

      _ ->
        conn
    end
  end

  def export_audit_logs(%{assigns: %{org: org, product: product, device: device}} = conn, _params) do
    conn =
      case AuditLogs.logs_for(device) do
        [] ->
          put_flash(conn, :error, "No audit logs exist for this device.")
          |> redirect(to: Routes.device_path(conn, :index, org.name, product.name))

        audit_logs ->
          audit_logs = AuditLogs.format_for_csv(audit_logs)

          conn
          |> send_download({:binary, audit_logs}, filename: "#{device.identifier}-audit-logs.csv")
      end

    {:noreply, conn}
  end
end

defmodule NervesHubWeb.DeviceController do
  use NervesHubWeb, :controller

  alias NervesHub.AuditLogs
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHubWeb.DeviceLive
  alias Ecto.Changeset

  plug(:validate_role, [product: :delete] when action in [:delete])
  plug(:validate_role, [product: :write] when action in [:new, :create, :edit])

  plug(
    :validate_role,
    [product: :read]
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
    |> render("new.html", changeset: %Changeset{data: %Device{}})
  end

  def create(%{assigns: %{org: org, product: product}} = conn, %{"device" => params}) do
    params
    |> Map.put("org_id", org.id)
    |> Map.put("product_id", product.id)
    |> Devices.create_device()
    |> case do
      {:ok, device} ->
        conn
        |> redirect(to: Routes.device_path(conn, :show, org.name, product.name, device.identifier))

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

  def edit(%{assigns: %{user: user, org: org, product: product, device: device}} = conn, _params) do
    conn
    |> live_render(
      DeviceLive.Edit,
      session: %{
        "auth_user_id" => user.id,
        "org_id" => org.id,
        "product_id" => product.id,
        "device_id" => device.id
      }
    )
  end

  def delete(%{assigns: %{org: org, product: product, device: device}} = conn, _params) do
    {:ok, _device} = Devices.delete_device(device)

    conn
    |> put_flash(:info, "Device deleted successfully.")
    |> redirect(to: Routes.device_path(conn, :index, org.name, product.name))
  end

  def console(
        %{assigns: %{user: user, org: org, product: product, device: device}} = conn,
        _params
      ) do
    meta = NervesHubDevice.Presence.find(device, %{})
    version = Map.get(meta, :console_version, "0.1.0")

    # Render based on NervesHubLink version to decide which
    # remote IEx console API needs to be handled. For now, leave
    # in support for rendering console via LiveView. This can
    # be cleaned up once it is no longer used
    cond do
      Version.match?(version, ">= 0.9.0") ->
        conn
        |> put_root_layout({NervesHubWeb.LayoutView, :console})
        |> put_layout(false)
        |> render("console.html",
          device: Map.merge(device, meta),
          console_available: meta[:console_available]
        )

      true ->
        conn
        |> live_render(
          DeviceLive.Console,
          session: %{
            "auth_user_id" => user.id,
            "org_id" => org.id,
            "product_id" => product.id,
            "device_id" => device.id
          }
        )
    end
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

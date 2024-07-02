defmodule NervesHubWeb.DeviceController do
  use NervesHubWeb, :controller

  alias NervesHub.AuditLogs

  plug(
    :validate_role,
    [org: :manage] when action in [:new, :create, :edit, :delete, :reboot, :toggle_updates]
  )

  plug(
    :validate_role,
    [org: :view]
    when action in [:index, :console, :show, :download_certificate, :export_audit_logs]
  )

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
          |> redirect(to: ~p"/org/#{org.name}/#{product.name}/devices")

        audit_logs ->
          audit_logs = AuditLogs.format_for_csv(audit_logs)

          conn
          |> send_download({:binary, audit_logs}, filename: "#{device.identifier}-audit-logs.csv")
      end

    {:noreply, conn}
  end
end

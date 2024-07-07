defmodule NervesHubWeb.DeviceController do
  use NervesHubWeb, :controller

  alias NervesHub.AuditLogs

  plug(NervesHubWeb.Plugs.Device)

  plug(
    :validate_role,
    [org: :view] when action in [:console, :download_certificate, :export_audit_logs]
  )

  def console(conn, _params) do
    conn
    |> put_root_layout({NervesHubWeb.LayoutView, :console})
    |> put_layout(false)
    |> render("console.html")
  end

  def download_certificate(%{assigns: %{device: device}} = conn, %{"serial" => serial}) do
    case Enum.find(device.device_certificates, &(&1.serial == serial)) do
      %{der: der} ->
        filename = "#{device.identifier}-cert.pem"
        pem = X509.Certificate.from_der!(der) |> X509.Certificate.to_pem()
        send_download(conn, {:binary, pem}, filename: filename)

      _ ->
        conn
    end
  end

  def export_audit_logs(%{assigns: %{product: product, device: device}} = conn, _params) do
    case AuditLogs.logs_for(device) do
      [] ->
        conn
        |> put_flash(:error, "No audit logs exist for this device.")
        |> redirect(to: ~p"/products/#{hashid(product)}/devices")

      audit_logs ->
        audit_logs = AuditLogs.format_for_csv(audit_logs)

        send_download(conn, {:binary, audit_logs},
          filename: "#{device.identifier}-audit-logs.csv"
        )
    end
  end
end

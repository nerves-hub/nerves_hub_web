defmodule NervesHubWeb.DeviceController do
  use NervesHubWeb, :controller

  alias NervesHub.AuditLogs
  alias NervesHubWeb.Plugs.Device

  plug(Device)

  plug(
    :validate_role,
    [org: :view] when action in [:console, :download_certificate, :export_audit_logs]
  )

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

  def export_audit_logs(%{assigns: %{org: org, product: product, device: device}} = conn, _params) do
    case AuditLogs.logs_for(device) do
      [] ->
        conn
        |> put_flash(:error, "No audit logs exist for this device.")
        |> redirect(to: ~p"/org/#{org}/#{product}/devices")

      audit_logs ->
        audit_logs = AuditLogs.format_for_csv(audit_logs)

        send_download(conn, {:binary, audit_logs}, filename: "#{device.identifier}-audit-logs.csv")
    end
  end
end

defmodule NervesHubWeb.DeviceControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.AuditLogs
  alias NervesHub.Devices.Certificates

  describe "certificates" do
    test "download certificate for device", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      [cert | _] = Certificates.get_device_certificates(device)

      conn = get(conn, ~p"/org/#{org}/#{product}/devices/#{device}/certificate/#{cert.serial}/download")

      [str] = Plug.Conn.get_resp_header(conn, "content-disposition")

      assert str =~ "attachment; filename"
      assert conn.resp_body =~ "-----BEGIN CERTIFICATE-----"
    end
  end

  describe "export_audit_logs" do
    test "downloads a CSV when audit logs exist", %{
      conn: conn,
      org: org,
      product: product,
      user: user,
      device: device
    } do
      AuditLogs.audit!(user, device, "test action")

      conn = get(conn, ~p"/org/#{org}/#{product}/devices/#{device}/audit_logs/download")

      assert response_content_type(conn, :csv) =~ "text/csv"

      assert Plug.Conn.get_resp_header(conn, "content-disposition") == [
               ~s(attachment; filename="#{device.identifier}-audit-logs.csv")
             ]

      assert conn.resp_body =~ "test action"
    end

    test "redirects when no audit logs exist", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      assert AuditLogs.logs_for(device) == []

      conn = get(conn, ~p"/org/#{org}/#{product}/devices/#{device}/audit_logs/download")

      assert redirected_to(conn) == ~p"/org/#{org}/#{product}/devices"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "No audit logs exist for this device."
    end
  end
end

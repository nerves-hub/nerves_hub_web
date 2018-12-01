defmodule NervesHubAPIWeb.CACertificateController do
  use NervesHubAPIWeb, :controller

  alias NervesHubCore.{Devices, Certificate}

  action_fallback(NervesHubAPIWeb.FallbackController)

  def index(%{assigns: %{org: org}} = conn, _params) do
    ca_certificates = Devices.get_ca_certificates(org)
    render(conn, "index.json", ca_certificates: ca_certificates)
  end

  def show(%{assigns: %{org: org}} = conn, %{"serial" => serial}) do
    with {:ok, ca_certificate} <- Devices.get_ca_certificate_by_org_and_serial(org, serial) do
      render(conn, "show.json", ca_certificate: ca_certificate)
    end
  end

  def create(%{assigns: %{org: org}} = conn, %{"cert" => cert64}) do
    with {:ok, cert_pem} <- Base.decode64(cert64),
         {:ok, cert} <- X509.Certificate.from_pem(cert_pem),
         serial <- Certificate.get_serial_number(cert),
         aki <- Certificate.get_aki(cert),
         ski <- Certificate.get_ski(cert),
         {not_before, not_after} <- Certificate.get_validity(cert),
         params <- %{
           serial: serial,
           aki: aki,
           ski: ski,
           not_before: not_before,
           not_after: not_after,
           der: X509.Certificate.to_der(cert)
         },
         {:ok, ca_certificate} <- Devices.create_ca_certificate(org, params) do
      conn
      |> put_status(:created)
      |> put_resp_header(
        "location",
        ca_certificate_path(conn, :show, org.name, ca_certificate.serial)
      )
      |> render("show.json", ca_certificate: ca_certificate)
    else
      {:error, :not_found} -> {:error, "error decoding certificate"}
      e -> e
    end
  end

  def delete(%{assigns: %{org: org}} = conn, %{"serial" => serial}) do
    with {:ok, ca_certificate} <- Devices.get_ca_certificate_by_org_and_serial(org, serial),
         {:ok, _ca_certificate} <- Devices.delete_ca_certificate(ca_certificate) do
      send_resp(conn, :no_content, "")
    end
  end
end

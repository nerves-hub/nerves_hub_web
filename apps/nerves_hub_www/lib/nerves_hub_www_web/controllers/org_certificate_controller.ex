defmodule NervesHubWWWWeb.OrgCertificateController do
  use NervesHubWWWWeb, :controller

  alias Ecto.Changeset
  alias NervesHubWebCore.{Devices, Certificate}
  alias NervesHubWebCore.Devices.CACertificate

  plug(:validate_role, [org: :delete] when action in [:delete])
  plug(:validate_role, [org: :write] when action in [:new, :create])
  plug(:validate_role, [org: :read] when action in [:index])

  def index(%{assigns: %{org: org}} = conn, _params) do
    conn
    |> render(
      "index.html",
      certificates: Devices.get_ca_certificates(org)
    )
  end

  def new(conn, _params) do
    render(conn, "new.html", changeset: %Changeset{data: %CACertificate{}})
  end

  def edit(%{assigns: %{org: org}} = conn, %{"serial" => serial}) do
    with {:ok, cert} <- Devices.get_ca_certificate_by_serial(serial),
         changeset <- Devices.CACertificate.changeset(cert, %{}) do
      render(conn, "edit.html", changeset: changeset, org: org, cert: cert)
    else
      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Certificate Authority not found")
        |> redirect(to: Routes.org_certificate_path(conn, :index, org.name))
    end
  end

  def update(%{assigns: %{org: org}} = conn, %{"ca_certificate" => params, "serial" => serial}) do
    with {:ok, cert} <- Devices.get_ca_certificate_by_serial(serial),
         {:ok, _cert} <- Devices.update_ca_certificate(cert, params) do
      conn
      |> put_flash(:info, "Certificate Authority updated")
      |> redirect(to: Routes.org_certificate_path(conn, :index, org.name))
    else
      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Error decoding certificate")
        |> redirect(to: Routes.org_certificate_path(conn, :index, org.name))

      {:error, changeset} ->
        conn
        |> put_flash(:error, "Error updating certificate")
        |> render("edit.html", changeset: changeset)
    end
  end

  def create(
        %{assigns: %{org: org}} = conn,
        %{"ca_certificate" => %{"cert" => %{path: upload_path}}} = params
      ) do
    with {:ok, cert_pem} <- File.read(upload_path),
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
           der: X509.Certificate.to_der(cert),
           description: Map.get(params["ca_certificate"], "description")
         },
         {:ok, _ca_certificate} <- Devices.create_ca_certificate(org, params) do
      conn
      |> put_flash(:info, "Certificate Authority created")
      |> redirect(to: Routes.org_certificate_path(conn, :index, org.name))
    else
      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Error decoding certificate")
        |> redirect(to: Routes.org_certificate_path(conn, :new, org.name))

      {:error, changeset} ->
        conn
        |> put_flash(:error, "Error creating certificate")
        |> render(
          "new.html",
          changeset: changeset
        )
    end
  end

  def delete(%{assigns: %{org: org}} = conn, %{"serial" => serial}) do
    with {:ok, ca_certificate} <- Devices.get_ca_certificate_by_org_and_serial(org, serial),
         {:ok, _ca_certificate} <- Devices.delete_ca_certificate(ca_certificate) do
      conn
      |> put_flash(:info, "Certificate successfully deleted")
      |> redirect(to: Routes.org_certificate_path(conn, :index, org.name))
    else
      _ ->
        conn
        |> put_flash(:error, "Failed to delete certificate. Please try again.")
        |> redirect(to: Routes.org_certificate_path(conn, :index, org.name))
    end
  end
end

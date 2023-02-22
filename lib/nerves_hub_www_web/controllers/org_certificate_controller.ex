defmodule NervesHubWWWWeb.OrgCertificateController do
  use NervesHubWWWWeb, :controller

  alias NervesHubWebCore.{Devices, Certificate}
  alias NervesHubWebCore.Devices.CACertificate
  alias NervesHubWebCore.Devices.CACertificate.CSR

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

  def new(%{assigns: %{org: org, user: user}} = conn, _params) do
    registration_code = CSR.generate_code()
    products = NervesHubWebCore.Products.get_products_by_user_and_org(user, org)

    conn
    |> put_session(:registration_code, registration_code)
    |> render("new.html",
      changeset: CACertificate.changeset(%CACertificate{}, %{}),
      registration_code: registration_code,
      products: products
    )
  end

  def edit(%{assigns: %{org: org, user: user}} = conn, %{"serial" => serial}) do
    with {:ok, cert} <- Devices.get_ca_certificate_by_serial(serial),
         changeset <- Devices.CACertificate.changeset(cert, %{}) do
      render(conn, "edit.html",
        changeset: changeset,
        org: org,
        serial: cert.serial,
        products: NervesHubWebCore.Products.get_products_by_user_and_org(user, org)
      )
    else
      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Certificate Authority not found")
        |> redirect(to: Routes.org_certificate_path(conn, :index, org.name))
    end
  end

  def update(%{assigns: %{org: org, user: user}} = conn, %{
        "ca_certificate" => params,
        "serial" => serial
      }) do
    with {:ok, cert} <- Devices.get_ca_certificate_by_serial(serial),
         {:ok, params} <- maybe_delete_jitp(params),
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
        |> render("edit.html",
          changeset: changeset,
          org: org,
          serial: serial,
          products: NervesHubWebCore.Products.get_products_by_user_and_org(user, org)
        )
    end
  end

  def create(
        %{assigns: %{org: org, user: user}} = conn,
        %{
          "ca_certificate" =>
            %{
              "cert" => %{path: cert_upload_path},
              "csr" => %{path: csr_upload_path}
            } = params
        }
      ) do
    with {:ok, cert_pem} <- File.read(cert_upload_path),
         {:ok, csr_pem} <- File.read(csr_upload_path),
         {:ok, cert} <- X509.Certificate.from_pem(cert_pem),
         {:ok, csr} <- Certificate.from_pem(csr_pem),
         :ok <- validate_csr(conn, cert, csr),
         serial <- Certificate.get_serial_number(cert),
         aki <- Certificate.get_aki(cert),
         ski <- Certificate.get_ski(cert),
         {cert_not_before, cert_not_after} = cert_validity <- Certificate.get_validity(cert),
         {_csr_not_before, _csr_not_after} = csr_validity <- Certificate.get_validity(csr),
         :ok <- check_validity(cert_validity),
         :ok <- check_validity(csr_validity),
         {:ok, params} <- maybe_delete_jitp(params),
         params <- %{
           serial: serial,
           aki: aki,
           ski: ski,
           not_before: cert_not_before,
           not_after: cert_not_after,
           der: X509.Certificate.to_der(cert),
           description: params["description"],
           jitp: params["jitp"]
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

      {:error, :cert_expired} ->
        conn
        |> put_flash(:error, "Certificate is expired")
        |> redirect(to: Routes.org_certificate_path(conn, :new, org.name))

      {:error, :invalid_csr} ->
        conn
        |> put_flash(:error, "Error validating certificate signing request")
        |> redirect(to: Routes.org_certificate_path(conn, :new, org.name))

      {:error, changeset} ->
        products = NervesHubWebCore.Products.get_products_by_user_and_org(user, org)

        conn
        |> put_flash(:error, "Error creating certificate")
        |> render(
          "new.html",
          changeset: changeset,
          products: products,
          registration_code: get_session(conn)["registration_code"]
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

  @spec validate_csr(Plug.Conn.t(), tuple(), tuple()) :: :ok | {:error, :invalid_csr}
  def validate_csr(conn, cert, csr) do
    session = get_session(conn)

    # This line could probably raise. the only way to get here is by mucking around in Session Storage
    code = session["registration_code"] || "nil check"

    CSR.validate_csr(code, cert, csr)
  end

  def check_validity({not_before, not_after}) do
    now = DateTime.utc_now()
    is_before? = DateTime.compare(now, not_before) != :gt
    is_after? = DateTime.compare(now, not_after) == :gt

    if is_before? or is_after? do
      {:error, :cert_expired}
    else
      :ok
    end
  end

  defp maybe_delete_jitp(%{"jitp" => %{"delete" => "", "id" => _id_str}} = params) do
    # View was loaded with existing JITP, but was unchanged
    {:ok, params}
  end

  defp maybe_delete_jitp(%{"jitp" => %{"delete" => ""}} = params) do
    # View was loaded but JITP not changed and will be missing pieces
    # so make sure not to include it in update
    {:ok, Map.delete(params, "jitp")}
  end

  defp maybe_delete_jitp(%{"jitp" => %{"jitp_toggle" => "false"}} = params) do
    # JITP is toggled off when creating cert
    {:ok, Map.delete(params, "jitp")}
  end

  defp maybe_delete_jitp(params), do: {:ok, params}
end

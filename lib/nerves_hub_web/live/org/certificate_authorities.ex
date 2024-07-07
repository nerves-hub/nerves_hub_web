defmodule NervesHubWeb.Live.Org.CertificateAuthorities do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.{Devices, Certificate}
  alias NervesHub.Devices.CACertificate
  alias NervesHub.Devices.CACertificate.CSR
  alias NervesHub.Products
  alias NervesHubWeb.LayoutView.DateTimeFormat
  alias NervesHubWeb.Components.{CAHelpers, Utils}

  embed_templates("certificate_authority_templates/*")

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    socket
    |> apply_action(socket.assigns.live_action, params)
    |> noreply()
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> page_title("Certificate Authorities - #{socket.assigns.org.name}")
    |> list_certificates()
    |> render_with(&list_cas_template/1)
  end

  defp apply_action(socket, :new, _params) do
    products = Products.get_products_by_user_and_org(socket.assigns.user, socket.assigns.org)

    socket
    |> page_title("Add Certificate Authorities - #{socket.assigns.org.name}")
    |> assign(:registration_code, CSR.generate_code())
    |> assign(:products, products)
    |> assign(:form, to_form(CACertificate.changeset(%CACertificate{}, %{})))
    |> assign(:show_jitp_form, false)
    |> allow_upload(:cert, accept: ~w(.pem), max_entries: 1, auto_upload: true)
    |> allow_upload(:csr, accept: ~w(.crt), max_entries: 1, auto_upload: true)
    |> render_with(&new_ca_template/1)
  end

  defp apply_action(socket, :edit, %{"serial" => serial}) do
    products = Products.get_products_by_user_and_org(socket.assigns.user, socket.assigns.org)

    with {:ok, cert} <- Devices.get_ca_certificate_by_serial(serial),
         changeset <- Devices.CACertificate.changeset(cert, %{}) do
      socket
      |> page_title("Edit Certificate Authorities - #{socket.assigns.org.name}")
      |> assign(:products, products)
      |> assign(:serial, cert.serial)
      |> assign(:form, to_form(changeset))
      |> assign(:show_jitp_form, show_jitp_form(changeset))
      |> render_with(&edit_ca_template/1)
    else
      {:error, :not_found} ->
        socket
        |> put_flash(:error, "Certificate Authority not found")
        |> push_patch(to: ~p"/orgs/#{hashid(socket.assigns.org)}/settings/certificates")
    end
  end

  @impl Phoenix.LiveView
  def handle_event("delete-certificate-authority", %{"certificate_serial" => serial}, socket) do
    authorized!(:"certificate_authority:delete", socket.assigns.org_user)

    with {:ok, ca_certificate} <-
           Devices.get_ca_certificate_by_org_and_serial(socket.assigns.org, serial),
         {:ok, _ca_certificate} <- Devices.delete_ca_certificate(ca_certificate) do
      socket
      |> put_flash(:info, "Certificate successfully deleted")
      |> list_certificates()
      |> noreply()
    else
      _ ->
        socket
        |> put_flash(
          :info,
          "Failed to delete certificate. Please contact support if this happens again."
        )
        |> noreply()
    end
  end

  def handle_event("update_certificate_authority", %{"ca_certificate" => ca_certificate}, socket) do
    authorized!(:"certificate_authority:update", socket.assigns.org_user)

    with {:ok, cert} <- Devices.get_ca_certificate_by_serial(socket.assigns.serial),
         {:ok, params} <- maybe_delete_jitp(ca_certificate),
         {:ok, _cert} <- Devices.update_ca_certificate(cert, params) do
      socket
      |> put_flash(:info, "Certificate Authority updated")
      |> push_patch(to: ~p"/orgs/#{hashid(socket.assigns.org)}/settings/certificates")
      |> noreply()
    else
      {:error, :not_found} ->
        socket
        |> put_flash(:error, "Error decoding certificate. Please contact support.")
        |> noreply()

      {:error, changeset} ->
        socket
        |> put_flash(:error, "Error updating certificate")
        |> assign(:form, to_form(changeset))
        |> assign(:show_jitp_form, show_jitp_form(changeset))
        |> noreply()
    end
  end

  def handle_event("validate_new_certificate_authority", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("add_certificate_authority", %{"ca_certificate" => params}, socket) do
    authorized!(:"certificate_authority:create", socket.assigns.org_user)

    socket = set_show_jitp_form(socket, params)

    with {:ok, cert} <- uploaded_cert(socket),
         {:ok, csr} <- uploaded_csr(socket),
         :ok <- CSR.validate_csr(socket.assigns.registration_code, cert, csr),
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
         {:ok, _ca_certificate} <- Devices.create_ca_certificate(socket.assigns.org, params) do
      socket
      |> put_flash(:info, "Certificate Authority created")
      |> push_patch(to: ~p"/orgs/#{hashid(socket.assigns.org)}/settings/certificates")
      |> noreply()
    else
      {:error, :empty_cert} ->
        {:noreply, put_flash(socket, :error, "Certificate Authority files required")}

      {:error, :empty_csr} ->
        {:noreply, put_flash(socket, :error, "Certificate Authority files required")}

      {:error, :not_found} ->
        {:noreply,
         put_flash(socket, :error, "Certificate Authority pem file is empty or invalid")}

      {:error, :cert_expired} ->
        {:noreply, put_flash(socket, :error, "Certificate is expired")}

      {:error, :invalid_csr} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Error validating certificate signing request. Please check if the right registration code was used."
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp list_certificates(socket) do
    certificates = Devices.get_ca_certificates(socket.assigns.org)
    assign(socket, :certificates, certificates)
  end

  defp uploaded_cert(socket) do
    case consume_uploaded_entries(socket, :cert, fn %{path: path}, _entry ->
           {:ok, cert_pem} = File.read(path)
           {:postpone, cert_pem}
         end) do
      [cert] -> X509.Certificate.from_pem(cert)
      [] -> {:error, :empty_cert}
    end
  end

  defp uploaded_csr(socket) do
    case consume_uploaded_entries(socket, :csr, fn %{path: path}, _entry ->
           {:ok, csr_pem} = File.read(path)
           {:ok, csr} = Certificate.from_pem(csr_pem)
           {:postpone, csr}
         end) do
      [csr] -> {:ok, csr}
      [] -> {:error, :empty_csr}
    end
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

  defp show_jitp_form(changeset) do
    !!changeset.data.jitp || !!changeset.changes[:jitp]
  end

  defp set_show_jitp_form(socket, params) do
    show_form = get_in(params, ["jitp", "jitp_toggle"]) == "true"
    assign(socket, :show_jitp_form, show_form)
  end

  defp maybe_delete_jitp(%{"jitp" => %{"delete" => "", "id" => _id_str}} = params) do
    # View was loaded with existing JITP, but was unchanged
    {:ok, params}
  end

  defp maybe_delete_jitp(%{"jitp" => %{"delete" => "true", "id" => _id_str}} = params) do
    # View was loaded with existing JITP and removed.
    {:ok, params}
  end

  defp maybe_delete_jitp(%{"jitp" => %{"delete" => "true"}} = params) do
    # View was loaded, JITP not changed, but the toggle was pressed a few times
    {:ok, Map.delete(params, "jitp")}
  end

  defp maybe_delete_jitp(%{"jitp" => %{"jitp_toggle" => "true"}} = params) do
    # JITP is toggled and should be saved
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

  defp upload_error_to_string(:too_large), do: "The file is too large"
  defp upload_error_to_string(:not_accepted), do: "You have selected an unrecognized file type"

  defp upload_error_to_string(:external_client_failure),
    do: "Something went wrong, please contact support"
end

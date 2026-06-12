defmodule NervesHubWeb.API.CACertificateController do
  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Certificate
  alias NervesHub.Devices
  alias NervesHub.Devices.CACertificate.CSR
  alias NervesHubWeb.API.Schemas.CACertificateSchemas

  tags(["CA Certificates"])
  security([%{}, %{"bearer_auth" => []}])

  plug(:validate_role, [org: :manage] when action in [:create, :delete])
  plug(:validate_role, [org: :view] when action in [:index, :show])

  operation(:index,
    summary: "List all CA Certificates for an Organization",
    parameters: [
      org_name: [
        in: :path,
        description: "Organization Name",
        type: :string,
        example: "example_org"
      ]
    ],
    responses: [
      ok: {"CA Certificate list response", "application/json", CACertificateSchemas.CACertificateListResponse}
    ]
  )

  def index(%{assigns: %{current_scope: %{org: org}}} = conn, _params) do
    ca_certificates = Devices.get_ca_certificates(org)
    render(conn, :index, ca_certificates: ca_certificates)
  end

  operation(:show,
    summary: "View an Organization's CA Certificate",
    parameters: [
      org_name: [
        in: :path,
        description: "Organization Name",
        type: :string,
        example: "example_org"
      ],
      serial: [
        in: :path,
        description: "CA Certificate Serial",
        type: :string,
        example: "5111552077003819958"
      ]
    ],
    responses: [
      ok: {"CA Certificate response", "application/json", CACertificateSchemas.CACertificate}
    ]
  )

  def show(%{assigns: %{current_scope: %{org: org}}} = conn, %{"serial" => serial}) do
    with {:ok, ca_certificate} <- Devices.get_ca_certificate_by_org_and_serial(org, serial) do
      render(conn, :show, ca_certificate: ca_certificate)
    end
  end

  operation(:verification_token,
    summary: "Generate a token for verifying the ownership of a CA Certificate",
    description: "Used to generate a short lived token for use during the creation of a CA Certificate.",
    parameters: [
      org_name: [
        in: :path,
        description: "Organization Name",
        type: :string,
        example: "example_org"
      ]
    ],
    responses: [
      ok:
        {"CA Certificate verification token response", "application/json",
         CACertificateSchemas.CACertificateVerificationTokenResponse}
    ]
  )

  def verification_token(%{assigns: %{current_scope: %{org: org}}} = conn, _params) do
    render(conn, :verification_token, token: CSR.generate_verification_token(org))
  end

  operation(:create,
    summary: "Create a CA Certificate for an Organization",
    parameters: [
      org_name: [
        in: :path,
        description: "Organization Name",
        type: :string,
        example: "example_org"
      ]
    ],
    request_body: {
      "CA Certificate creation request body",
      "application/json",
      CACertificateSchemas.CACertificateCreationRequest,
      required: true
    },
    responses: [
      ok: {"CA Certificate response", "application/json", CACertificateSchemas.CACertificate}
    ]
  )

  def create(
        %{assigns: %{current_scope: %{org: org}}} = conn,
        %{"cert" => cert64, "verification_cert" => verification_cert64} = params
      ) do
    with {:ok, cert_pem} <- Base.decode64(cert64),
         {:ok, cert} <- X509.Certificate.from_pem(cert_pem),
         serial = Certificate.get_serial_number(cert),
         aki = Certificate.get_aki(cert),
         ski = Certificate.get_ski(cert),
         {not_before, not_after} <- Certificate.get_validity(cert),
         {:ok, verification_cert_pem} <- Base.decode64(verification_cert64),
         {:ok, verification_cert} <- X509.Certificate.from_pem(verification_cert_pem),
         :ok <- CSR.validate_cert_ownership(org, cert, verification_cert),
         params = %{
           serial: serial,
           aki: aki,
           ski: ski,
           not_before: not_before,
           not_after: not_after,
           der: X509.Certificate.to_der(cert),
           description: Map.get(params, "description"),
           jitp: params["jitp"]
         },
         {:ok, ca_cert} <- Devices.create_ca_certificate(org, params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/orgs/#{org.name}/ca_certificates/#{ca_cert.serial}")
      |> render(:show, ca_certificate: ca_cert)
    else
      {:error, :not_found} ->
        {:error, {:certificate_decoding_error, "Error decoding certificate"}}

      {:error, :invalid_csr} ->
        {:error, {:invalid_csr, "CA Certificate ownership verification failed"}}

      e ->
        e
    end
  end

  def create(_conn, _params) do
    {:error, {:cert_or_verification_cert_missing, "The CA certificate or verification certificate is missing"}}
  end

  operation(:delete,
    summary: "Delete an Organization's CA Certificate",
    parameters: [
      org_name: [
        in: :path,
        description: "Organization Name",
        type: :string,
        example: "example_org"
      ],
      serial: [
        in: :path,
        description: "CA Certificate Serial",
        type: :string,
        example: "5111552077003819958"
      ]
    ],
    responses: [
      no_content: "Empty response"
    ]
  )

  def delete(%{assigns: %{current_scope: %{org: org}}} = conn, %{"serial" => serial}) do
    with {:ok, ca_certificate} <- Devices.get_ca_certificate_by_org_and_serial(org, serial),
         {:ok, _ca_certificate} <- Devices.delete_ca_certificate(ca_certificate) do
      send_resp(conn, :no_content, "")
    end
  end
end

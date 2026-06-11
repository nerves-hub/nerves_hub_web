defmodule NervesHubWeb.API.CACertificateControllerTest do
  use NervesHubWeb.APIConnCase, async: true

  alias NervesHub.Certificate
  alias NervesHub.Devices
  alias X509.Certificate.Extension

  describe "index" do
    test "lists all ca certificates", %{conn: conn, org: org} do
      conn = get(conn, Routes.api_ca_certificate_path(conn, :index, org.name))
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "create ca certificate" do
    test "renders key when data is valid", %{conn: conn, org: org} do
      ca_key = X509.PrivateKey.new_ec(:secp256r1)
      ca_cert = X509.Certificate.self_signed(ca_key, "CN=#{org.name}", template: :root_ca)
      serial = X509.Certificate.serial(ca_cert) |> to_string()
      ca_cert_pem = X509.Certificate.to_pem(ca_cert)

      conn = get(conn, ~p"/api/orgs/#{org.name}/ca_certificates/verification_token")
      assert %{"data" => %{"verification_token" => verification_token}} = json_response(conn, 200)

      signing_key = X509.PrivateKey.new_rsa(2048)

      san =
        Extension.subject_alt_name(uniformResourceIdentifier: ~c"urn:nerveshub:verify:#{verification_token}")

      signing_csr = X509.CSR.new(signing_key, "/CN=ownership-verification", extension_request: [san])

      signing_san =
        signing_csr
        |> X509.CSR.extension_request()
        |> Enum.find(fn ext -> elem(ext, 1) == {2, 5, 29, 17} end)

      verification_cert =
        signing_csr
        |> X509.CSR.public_key()
        |> X509.Certificate.new(X509.CSR.subject(signing_csr), ca_cert, ca_key,
          extensions: [subject_alt_name: signing_san]
        )

      verification_cert_pem = X509.Certificate.to_pem(verification_cert)

      description = "My ca"

      params = %{
        cert: Base.encode64(ca_cert_pem),
        verification_cert: Base.encode64(verification_cert_pem),
        description: description
      }

      conn = post(conn, ~p"/api/orgs/#{org.name}/ca_certificates", params)

      assert %{"data" => resp_data} = json_response(conn, 201)

      assert %{"serial" => ^serial} = resp_data
      assert %{"description" => ^description} = resp_data
    end

    test "supports valid JITP", %{conn: conn, org: org, product: %{id: pid, name: product_name}} do
      ca_key = X509.PrivateKey.new_ec(:secp256r1)
      ca_cert = X509.Certificate.self_signed(ca_key, "CN=#{org.name}", template: :root_ca)
      serial = X509.Certificate.serial(ca_cert) |> to_string()
      ca_cert_pem = X509.Certificate.to_pem(ca_cert)

      conn = get(conn, ~p"/api/orgs/#{org.name}/ca_certificates/verification_token")
      assert %{"data" => %{"verification_token" => verification_token}} = json_response(conn, 200)

      signing_key = X509.PrivateKey.new_rsa(2048)

      san =
        Extension.subject_alt_name(uniformResourceIdentifier: ~c"urn:nerveshub:verify:#{verification_token}")

      signing_csr = X509.CSR.new(signing_key, "/CN=ownership-verification", extension_request: [san])

      signing_san =
        signing_csr
        |> X509.CSR.extension_request()
        |> Enum.find(fn ext -> elem(ext, 1) == {2, 5, 29, 17} end)

      verification_cert =
        signing_csr
        |> X509.CSR.public_key()
        |> X509.Certificate.new(X509.CSR.subject(signing_csr), ca_cert, ca_key,
          extensions: [subject_alt_name: signing_san]
        )

      verification_cert_pem = X509.Certificate.to_pem(verification_cert)

      description = "My ca"

      jitp = %{description: "Jitter", tags: ["howdy"], product_id: pid}

      params = %{
        cert: Base.encode64(ca_cert_pem),
        description: description,
        jitp: jitp,
        verification_cert: Base.encode64(verification_cert_pem)
      }

      conn = post(conn, Routes.api_ca_certificate_path(conn, :create, org.name), params)
      resp_data = json_response(conn, 201)["data"]
      assert %{"serial" => ^serial} = resp_data
      assert %{"description" => ^description} = resp_data

      assert %{"description" => "Jitter", "tags" => ["howdy"], "product_name" => ^product_name} =
               resp_data["jitp"]
    end

    test "renders errors when the verification fails", %{conn: conn, org: org} do
      ca_key = X509.PrivateKey.new_ec(:secp256r1)
      ca_cert = X509.Certificate.self_signed(ca_key, "CN=#{org.name}", template: :root_ca)
      ca_cert_pem = X509.Certificate.to_pem(ca_cert)

      signing_key = X509.PrivateKey.new_rsa(2048)

      # no SAN extension, should fail
      signing_csr = X509.CSR.new(signing_key, "/CN=boop")

      verification_cert =
        signing_csr
        |> X509.CSR.public_key()
        |> X509.Certificate.new(X509.CSR.subject(signing_csr), ca_cert, ca_key)

      verification_cert_pem = X509.Certificate.to_pem(verification_cert)

      description = "My ca"

      params = %{
        cert: Base.encode64(ca_cert_pem),
        verification_cert: Base.encode64(verification_cert_pem),
        description: description
      }

      conn = post(conn, ~p"/api/orgs/#{org.name}/ca_certificates", params)

      assert %{"errors" => resp_data} = json_response(conn, 422)
      assert resp_data["detail"] == "CA Certificate ownership verification failed"
    end

    test "renders errors when data is invalid", %{conn: conn, org: org} do
      conn = post(conn, ~p"/api/orgs/#{org.name}/ca_certificates", cert: "")

      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "delete ca_certificate" do
    setup [:create_ca_certificate]

    test "deletes chosen ca_certificate", %{conn: conn, org: org, ca_certificate: ca_certificate} do
      conn =
        delete(
          conn,
          Routes.api_ca_certificate_path(conn, :delete, org.name, ca_certificate.serial)
        )

      assert response(conn, 204)

      conn =
        get(conn, Routes.api_ca_certificate_path(conn, :show, org.name, ca_certificate.serial))

      assert response(conn, 404)
    end
  end

  test "includes jitp when available", context do
    params = %{jitp: %{description: "Jitter", tags: ["howdy"], product_id: context.product.id}}
    {:ok, %{ca_certificate: ca_cert}} = create_ca_certificate(context, params)

    conn =
      get(
        context.conn,
        Routes.api_ca_certificate_path(context.conn, :show, context.org.name, ca_cert.serial)
      )

    assert json_response(conn, 200)["data"]["jitp"] == %{
             "description" => "Jitter",
             "tags" => ["howdy"],
             "product_name" => context.product.name
           }
  end

  defp create_ca_certificate(%{org: org}, params \\ %{}) do
    ca_key = X509.PrivateKey.new_ec(:secp256r1)
    ca = X509.Certificate.self_signed(ca_key, "CN=#{org.name}", template: :root_ca)
    {not_before, not_after} = Certificate.get_validity(ca)

    params =
      %{
        serial: Certificate.get_serial_number(ca),
        aki: Certificate.get_aki(ca),
        ski: Certificate.get_ski(ca),
        not_before: not_before,
        not_after: not_after,
        der: X509.Certificate.to_der(ca),
        description: "My CA"
      }
      |> Map.merge(params)

    {:ok, ca_certificate} = Devices.create_ca_certificate(org, params)
    {:ok, %{ca_certificate: ca_certificate}}
  end
end

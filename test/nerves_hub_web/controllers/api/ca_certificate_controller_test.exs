defmodule NervesHubWeb.API.CACertificateControllerTest do
  use NervesHubWeb.APIConnCase, async: true

  alias NervesHub.Certificate
  alias NervesHub.Devices

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
      description = "My ca"

      params = %{cert: Base.encode64(ca_cert_pem), description: description}

      conn = post(conn, Routes.api_ca_certificate_path(conn, :create, org.name), params)
      resp_data = json_response(conn, 201)["data"]
      assert %{"serial" => ^serial} = resp_data
      assert %{"description" => ^description} = resp_data
    end

    test "supports valid JITP", %{conn: conn, org: org, product: %{id: pid, name: product_name}} do
      ca_key = X509.PrivateKey.new_ec(:secp256r1)
      ca_cert = X509.Certificate.self_signed(ca_key, "CN=#{org.name}", template: :root_ca)
      serial = X509.Certificate.serial(ca_cert) |> to_string()
      ca_cert_pem = X509.Certificate.to_pem(ca_cert)
      description = "My ca"

      jitp = %{description: "Jitter", product_id: pid, tags: ["howdy"]}
      params = %{cert: Base.encode64(ca_cert_pem), description: description, jitp: jitp}

      conn = post(conn, Routes.api_ca_certificate_path(conn, :create, org.name), params)
      resp_data = json_response(conn, 201)["data"]
      assert %{"serial" => ^serial} = resp_data
      assert %{"description" => ^description} = resp_data

      assert %{"description" => "Jitter", "product_name" => ^product_name, "tags" => ["howdy"]} =
               resp_data["jitp"]
    end

    test "renders errors when data is invalid", %{conn: conn, org: org} do
      conn = post(conn, Routes.api_ca_certificate_path(conn, :create, org.name), cert: "")

      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "delete ca_certificate" do
    setup [:create_ca_certificate]

    test "deletes chosen ca_certificate", %{ca_certificate: ca_certificate, conn: conn, org: org} do
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
    params = %{jitp: %{description: "Jitter", product_id: context.product.id, tags: ["howdy"]}}
    {:ok, %{ca_certificate: ca_cert}} = create_ca_certificate(context, params)

    conn =
      get(
        context.conn,
        Routes.api_ca_certificate_path(context.conn, :show, context.org.name, ca_cert.serial)
      )

    assert json_response(conn, 200)["data"]["jitp"] == %{
             "description" => "Jitter",
             "product_name" => context.product.name,
             "tags" => ["howdy"]
           }
  end

  defp create_ca_certificate(%{org: org}, params \\ %{}) do
    ca_key = X509.PrivateKey.new_ec(:secp256r1)
    ca = X509.Certificate.self_signed(ca_key, "CN=#{org.name}", template: :root_ca)
    {not_before, not_after} = Certificate.get_validity(ca)

    params =
      %{
        aki: Certificate.get_aki(ca),
        der: X509.Certificate.to_der(ca),
        description: "My CA",
        not_after: not_after,
        not_before: not_before,
        serial: Certificate.get_serial_number(ca),
        ski: Certificate.get_ski(ca)
      }
      |> Map.merge(params)

    {:ok, ca_certificate} = Devices.create_ca_certificate(org, params)
    {:ok, %{ca_certificate: ca_certificate}}
  end
end

defmodule NervesHubWeb.Live.Org.CertificateAuthoritiesTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Fixtures
  alias NervesHub.{Certificate, Devices}
  alias NervesHubWeb.Components.Utils

  describe "index" do
    test "lists all device(ca) certificates", %{conn: conn, org: org} do
      %{db_cert: db1_cert} = Fixtures.ca_certificate_fixture(org)
      %{db_cert: db2_cert} = Fixtures.ca_certificate_fixture(org)

      conn
      |> visit("/org/#{org.name}/settings/certificates")
      |> assert_has("h1", text: "Certificate Authorities")
      |> assert_has("code", text: Utils.format_serial(db1_cert.serial))
      |> assert_has("code", text: Utils.format_serial(db2_cert.serial))
    end
  end

  describe "new" do
    test "CA is created on success", %{conn: conn, org: org, tmp_dir: tmp_dir} do
      description = "My ca"

      ca_file_path = Fixtures.device_certificate_authority_file()
      ca_key_file_path = Fixtures.device_certificate_authority_key_file()

      conn
      |> visit("/org/#{org.name}/settings/certificates/new")
      |> assert_has("h1", text: "New Certificate Authority")
      |> unwrap(fn view ->
        code = registration_code(view)

        %{verification_cert_crt: verification_cert_crt} =
          Fixtures.generate_certificate_authority_csr(
            ca_file_path,
            ca_key_file_path,
            code,
            tmp_dir
          )

        upload_file(view, "rootCA.pem", ca_file_path, :cert)
        upload_file(view, "verificationCert.crt", verification_cert_crt, :csr)
      end)
      |> fill_in("Description", with: description)
      |> click_button("Create Certificate")
      |> assert_path("/org/#{org.name}/settings/certificates")
      |> assert_has("div", text: "Certificate Authority created")
      |> assert_has("h1", text: "Certificate Authorities")
      |> assert_has("tr > td > code")

      {:ok, ca} = File.read!(ca_file_path) |> X509.Certificate.from_pem()

      serial = Certificate.get_serial_number(ca)

      assert {:ok, %{description: ^description, serial: ^serial}} =
               Devices.get_ca_certificate_by_serial(serial)
    end

    test "renders errors when cert is invalid", %{conn: conn, org: org, tmp_dir: tmp_dir} do
      ca_file_path = Fixtures.device_certificate_authority_file()
      ca_key_file_path = Fixtures.device_certificate_authority_key_file()

      conn
      |> visit("/org/#{org.name}/settings/certificates/new")
      |> assert_has("h1", text: "New Certificate Authority")
      |> unwrap(fn view ->
        code = registration_code(view)

        %{verification_cert_crt: verification_cert_crt} =
          Fixtures.generate_certificate_authority_csr(
            ca_file_path,
            ca_key_file_path,
            code,
            tmp_dir
          )

        bad_ca_file_path = Fixtures.bad_device_certificate_authority_file()

        upload_file(view, "rootCA.pem", bad_ca_file_path, :cert)
        upload_file(view, "verificationCert.crt", verification_cert_crt, :csr)
      end)
      |> click_button("Create Certificate")
      |> assert_path("/org/#{org.name}/settings/certificates/new")
      |> assert_has("div", text: "Certificate Authority pem file is empty or invalid")

      assert [] = Devices.get_ca_certificates(org)
    end

    test "renders errors when csr is invalid", %{conn: conn, org: org, tmp_dir: tmp_dir} do
      ca_file_path = Fixtures.device_certificate_authority_file()
      ca_key_file_path = Fixtures.device_certificate_authority_key_file()

      %{verification_cert_crt: verification_cert_crt} =
        Fixtures.generate_certificate_authority_csr(
          ca_file_path,
          ca_key_file_path,
          "oops",
          tmp_dir
        )

      conn
      |> visit("/org/#{org.name}/settings/certificates/new")
      |> assert_has("h1", text: "New Certificate Authority")
      |> unwrap(fn view ->
        upload_file(view, "rootCA.pem", ca_file_path, :cert)
        upload_file(view, "verificationCert.crt", verification_cert_crt, :csr)
      end)
      |> click_button("Create Certificate")
      |> assert_path("/org/#{org.name}/settings/certificates/new")
      |> assert_has("div",
        text:
          "Error validating certificate signing request. Please check if the right registration code was used."
      )

      assert [] = Devices.get_ca_certificates(org)
    end

    @tag timeout: :infinity
    test "create with JITP", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)

      ca_file_path = Fixtures.device_certificate_authority_file()
      ca_key_file_path = Fixtures.device_certificate_authority_key_file()

      description = "My ca"

      conn
      |> visit("/org/#{org.name}/settings/certificates/new")
      |> assert_has("h1", text: "New Certificate Authority")
      |> unwrap(fn view ->
        code = registration_code(view)

        %{verification_cert_crt: verification_cert_crt} =
          Fixtures.generate_certificate_authority_csr(
            ca_file_path,
            ca_key_file_path,
            code,
            tmp_dir
          )

        upload_file(view, "rootCA.pem", ca_file_path, :cert)
        upload_file(view, "verificationCert.crt", verification_cert_crt, :csr)
      end)
      |> fill_in("Description", with: description)
      |> check("Enable Just In Time Provisioning")
      |> fill_in("JITP Description", with: "a jitp description")
      |> fill_in("JITP Tags", with: "prod")
      |> select(product.name, from: "JITP Product")
      |> click_button("Create Certificate")
      |> assert_path("/org/#{org.name}/settings/certificates")
      |> assert_has("div", text: "Certificate Authority created")
      |> assert_has("h1", text: "Certificate Authorities")
      |> assert_has("tr > td > code")

      {:ok, ca} = File.read!(ca_file_path) |> X509.Certificate.from_pem()

      serial = Certificate.get_serial_number(ca)

      assert {:ok,
              %{
                description: ^description,
                serial: ^serial,
                jitp: %{tags: ["prod"], description: "a jitp description"}
              }} = Devices.get_ca_certificate_by_serial(serial)
    end
  end

  describe "delete" do
    test "deletes  certificate authority", %{conn: conn, org: org} do
      %{db_cert: ca} = Fixtures.ca_certificate_fixture(org)

      conn
      |> visit("/org/#{org.name}/settings/certificates")
      |> assert_has("h1", text: "Certificate Authorities")
      |> assert_has("code", text: Utils.format_serial(ca.serial))
      |> click_link("Delete")
      |> assert_has("div", text: "Certificate successfully deleted")
      |> refute_has("code", text: Utils.format_serial(ca.serial))

      assert {:error, :not_found} = Devices.get_ca_certificate_by_serial(ca.serial)
    end
  end

  describe "update" do
    test "description can be updated", %{conn: conn, org: org} do
      %{db_cert: %{serial: serial}} = Fixtures.ca_certificate_fixture(org)

      conn
      |> visit("/org/#{org.name}/settings/certificates/#{serial}/edit")
      |> assert_has("h1", text: "Edit Certificate Authority")
      |> fill_in("Description", with: "a new description")
      |> click_button("Update Certificate")
      |> assert_path("/org/#{org.name}/settings/certificates")
      |> assert_has("div", text: "Certificate Authority updated")

      assert {:ok, %{description: "a new description", serial: ^serial}} =
               Devices.get_ca_certificate_by_serial(serial)
    end

    test "update fails when description is blank", %{conn: conn, user: user, org: org} do
      %{db_cert: %{serial: serial}} = Fixtures.ca_certificate_fixture(org)
      product = Fixtures.product_fixture(user, org)

      conn
      |> visit("/org/#{org.name}/settings/certificates/#{serial}/edit")
      |> assert_has("h1", text: "Edit Certificate Authority")
      |> check("Enable Just In Time Provisioning")
      |> fill_in("JITP Description", with: "")
      |> fill_in("JITP Tags", with: "prod")
      |> select(product.name, from: "JITP Product")
      |> click_button("Update Certificate")
      |> assert_path("/org/#{org.name}/settings/certificates/#{serial}/edit")
      |> assert_has("div", text: "Error updating certificate")
      |> assert_has("span", text: "can't be blank")
    end
  end

  defp registration_code(view) do
    view
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find("#registration_code > code")
    |> Enum.map(&Floki.text(&1, sep: " "))
    |> List.first()
    |> String.trim()
  end

  defp upload_file(view, file_name, file_path, form_field) do
    csr =
      file_input(view, "form", form_field, [
        %{
          last_modified: 1_594_171_879_000,
          name: file_name,
          content: File.read!(file_path)
        }
      ])

    render_upload(csr, file_name)
  end
end

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
      |> visit("/orgs/#{org.name}/settings/certificates")
      |> assert_has("h1", text: "Certificate Authorities")
      |> assert_has("code", text: Utils.format_serial(db1_cert.serial))
      |> assert_has("code", text: Utils.format_serial(db2_cert.serial))
    end
  end

  describe "new" do
    @tag :tmp_dir
    test "CA is created on success", %{conn: conn, org: org, tmp_dir: tmp_dir} do
      conn =
        conn
        |> visit("/orgs/#{org.name}/settings/certificates/new")
        |> assert_has("h1", text: "New Certificate Authority")

      code =
        conn.view
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("#registration_code > code")
        |> Enum.map(&Floki.text(&1, sep: " "))
        |> List.first()
        |> String.trim()

      ca_file_path = Fixtures.device_certificate_authority_file()
      ca_key_file_path = Fixtures.device_certificate_authority_key_file()

      %{verification_cert_crt: verification_cert_crt} =
        Fixtures.generate_certificate_authority_csr(ca_file_path, ca_key_file_path, code, tmp_dir)

      {:ok, ca} = File.read!(ca_file_path) |> X509.Certificate.from_pem()

      serial = Certificate.get_serial_number(ca)

      description = "My ca"

      cert =
        file_input(conn.view, "form", :cert, [
          %{
            last_modified: 1_594_171_879_000,
            name: "rootCA.pem",
            content: File.read!(ca_file_path)
          }
        ])

      render_upload(cert, "rootCA.pem")

      csr =
        file_input(conn.view, "form", :csr, [
          %{
            last_modified: 1_594_171_879_000,
            name: "verificationCert.crt",
            content: File.read!(verification_cert_crt)
          }
        ])

      render_upload(csr, "verificationCert.crt")

      conn
      |> fill_in("Description", with: description)
      |> click_button("Create Certificate")
      |> assert_path("/orgs/#{org.name}/settings/certificates")
      |> assert_has("div", text: "Certificate Authority created")
      |> assert_has("h1", text: "Certificate Authorities")
      |> assert_has("tr > td > code")

      assert {:ok, %{description: ^description, serial: ^serial}} =
               Devices.get_ca_certificate_by_serial(serial)
    end
  end

  describe "delete" do
    test "deletes  certificate authority", %{conn: conn, org: org} do
      %{db_cert: ca} = Fixtures.ca_certificate_fixture(org)

      conn
      |> visit("/orgs/#{org.name}/settings/certificates")
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
      |> visit("/orgs/#{org.name}/settings/certificates/#{serial}/edit")
      |> assert_has("h1", text: "Edit Certificate Authority")
      |> fill_in("Description", with: "a new description")
      |> click_button("Update Certificate")
      |> assert_path("/orgs/#{org.name}/settings/certificates")
      |> assert_has("div", text: "Certificate Authority updated")

      assert {:ok, %{description: "a new description", serial: ^serial}} =
               Devices.get_ca_certificate_by_serial(serial)
    end

    # test "update fails when description is blank", %{conn: conn, user: user, org: org} do
    #   %{db_cert: %{serial: serial}} = Fixtures.ca_certificate_fixture(org)

    #   conn
    #   |> visit("/orgs/#{org.name}/settings/certificates/#{serial}/edit")
    #   |> assert_has("h1", text: "Edit Certificate Authority")
    #   |> fill_in("Description", with: "a new description")
    #   |> click_button("Update Certificate")
    #   |> assert_path("/orgs/#{org.name}/settings/certificates/#{serial}/edit")
    #   |> assert_has("div", text: "Error updating certificate")
    #   |> assert_has("p", text: "Can't be blank")

    #   {:ok, ca} = Devices.get_ca_certificate_by_serial(serial)

    #   refute "a new description" == ca.description
    # end
  end

  #   describe "create" do
  #

  #     @tag :tmp_dir
  #     test "renders errors when cert is invalid", %{conn: conn, org: org, tmp_dir: tmp_dir} do
  #       conn = get(conn, Routes.org_certificate_path(conn, :new, org.name))
  #       session = Plug.Conn.get_session(conn)
  #       code = session["registration_code"]
  #       ca_file_path = Fixtures.device_certificate_authority_file()
  #       ca_key_file_path = Fixtures.device_certificate_authority_key_file()

  #       %{verification_cert_pem: verification_cert_pem} =
  #         Fixtures.generate_certificate_authority_csr(ca_file_path, ca_key_file_path, code, tmp_dir)

  #       bad_ca_file_path = Fixtures.bad_device_certificate_authority_file()

  #       cert_upload = %Plug.Upload{path: bad_ca_file_path}
  #       csr_upload = %Plug.Upload{path: verification_cert_pem}

  #       params = %{ca_certificate: %{cert: cert_upload, csr: csr_upload}}

  #       conn = post(conn, Routes.org_certificate_path(conn, :create, org.name), params)
  #       assert redirected_to(conn) == Routes.org_certificate_path(conn, :new, org.name)
  #       conn = get(conn, Routes.org_certificate_path(conn, :new, org.name))
  #       assert html_response(conn, 200) =~ "Error decoding certificate"
  #     end

  #     @tag :tmp_dir
  #     test "renders errors when params are invalid", %{conn: conn, org: org, tmp_dir: tmp_dir} do
  #       conn = get(conn, Routes.org_certificate_path(conn, :new, org.name))
  #       session = Plug.Conn.get_session(conn)
  #       code = session["registration_code"]
  #       ca_file_path = Fixtures.device_certificate_authority_file()
  #       ca_key_file_path = Fixtures.device_certificate_authority_key_file()

  #       %{verification_cert_pem: verification_cert_pem} =
  #         Fixtures.generate_certificate_authority_csr(ca_file_path, ca_key_file_path, code, tmp_dir)

  #       {:ok, ca} = File.read!(ca_file_path) |> X509.Certificate.from_pem()
  #       serial = Certificate.get_serial_number(ca)
  #       description = 123

  #       cert_upload = %Plug.Upload{path: ca_file_path}
  #       csr_upload = %Plug.Upload{path: verification_cert_pem}
  #       params = %{ca_certificate: %{cert: cert_upload, csr: csr_upload, description: description}}

  #       conn = post(conn, Routes.org_certificate_path(conn, :create, org.name), params)
  #       assert html_response(conn, 200) =~ "Error creating certificate"

  #       assert {:error, :not_found} = Devices.get_ca_certificate_by_serial(serial)
  #     end

  #     @tag :tmp_dir
  #     test "renders errors when csr is invalid", %{conn: conn, org: org, tmp_dir: tmp_dir} do
  #       ca_file_path = Fixtures.device_certificate_authority_file()
  #       ca_key_file_path = Fixtures.device_certificate_authority_key_file()

  #       %{verification_cert_pem: verification_cert_pem} =
  #         Fixtures.generate_certificate_authority_csr(
  #           ca_file_path,
  #           ca_key_file_path,
  #           "oops",
  #           tmp_dir
  #         )

  #       {:ok, ca} = File.read!(ca_file_path) |> X509.Certificate.from_pem()
  #       serial = Certificate.get_serial_number(ca)
  #       description = "test"

  #       cert_upload = %Plug.Upload{path: ca_file_path}
  #       csr_upload = %Plug.Upload{path: verification_cert_pem}
  #       params = %{ca_certificate: %{cert: cert_upload, csr: csr_upload, description: description}}

  #       conn = post(conn, Routes.org_certificate_path(conn, :create, org.name), params)
  #       assert redirected_to(conn) == Routes.org_certificate_path(conn, :new, org.name)

  #       assert {:error, :not_found} = Devices.get_ca_certificate_by_serial(serial)
  #     end

  #     @tag :tmp_dir
  #     @tag timeout: :infinity
  #     test "create with JITP", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
  #       conn = get(conn, Routes.org_certificate_path(conn, :new, org.name))
  #       session = Plug.Conn.get_session(conn)
  #       code = session["registration_code"]
  #       ca_file_path = Fixtures.device_certificate_authority_file()
  #       ca_key_file_path = Fixtures.device_certificate_authority_key_file()
  #       product = Fixtures.product_fixture(user, org)

  #       %{verification_cert_pem: verification_cert_pem} =
  #         Fixtures.generate_certificate_authority_csr(ca_file_path, ca_key_file_path, code, tmp_dir)

  #       {:ok, ca} = File.read!(ca_file_path) |> X509.Certificate.from_pem()
  #       serial = Certificate.get_serial_number(ca)
  #       description = "My JITP ca"

  #       cert_upload = %Plug.Upload{path: ca_file_path}
  #       csr_upload = %Plug.Upload{path: verification_cert_pem}

  #       params = %{
  #         ca_certificate: %{
  #           cert: cert_upload,
  #           csr: csr_upload,
  #           description: description,
  #           jitp: %{tags: ["prod"], description: "jitp", product_id: product.id}
  #         }
  #       }

  #       conn = post(conn, Routes.org_certificate_path(conn, :create, org.name), params)
  #       assert redirected_to(conn) == Routes.org_certificate_path(conn, :index, org.name)

  #       assert {:ok,
  #               %{
  #                 description: ^description,
  #                 serial: ^serial,
  #                 jitp: %{tags: ["prod"], description: "jitp"}
  #               }} = Devices.get_ca_certificate_by_serial(serial)
  #     end
  #   end

  #   describe "edit" do
  #     test "renders form", %{conn: conn, org: org} do
  #       %{db_cert: ca} = Fixtures.ca_certificate_fixture(org)
  #       conn = get(conn, Routes.org_certificate_path(conn, :edit, org.name, ca.serial))
  #       assert html_response(conn, 200) =~ "Edit Certificate Authority"
  #     end

  #     test "redirects to index when not found", %{conn: conn, org: org} do
  #       conn = get(conn, Routes.org_certificate_path(conn, :edit, org.name, "unknown-serial"))
  #       assert redirected_to(conn, 302) =~ Routes.org_certificate_path(conn, :index, org.name)
  #     end
  #   end
end

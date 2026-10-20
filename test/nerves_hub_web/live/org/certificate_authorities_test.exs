defmodule NervesHubWeb.Live.Org.CertificateAuthoritiesTest do
  use NervesHubWeb.ConnCase.Browser, async: false
  use Mimic

  alias NervesHub.Certificate
  alias NervesHub.Devices.CACertificate.CSR
  alias NervesHub.Devices.CACertificates
  alias NervesHub.Fixtures
  alias NervesHubWeb.Components.Utils
  alias X509.Certificate.Validity

  @expired Validity.new(~U[2020-01-01 00:00:00Z], ~U[2025-01-01 00:00:00Z])

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

  describe "index device counts" do
    test "counts the devices using each CA", %{conn: conn, org: org, product: product, firmware: firmware} do
      %{db_cert: in_use} = ca = Fixtures.ca_certificate_fixture(org)
      %{db_cert: unused} = Fixtures.ca_certificate_fixture(org)

      for _ <- 1..2 do
        device = Fixtures.device_fixture(org, product, firmware)
        Fixtures.device_certificate_fixture_for_ca(device, ca)
      end

      conn
      |> visit("/org/#{org.name}/settings/certificates")
      |> assert_has("th", text: "Devices")
      |> assert_has("#ca-#{in_use.id}-device-count", text: "2")
      |> assert_has("#ca-#{unused.id}-device-count", text: "0")
    end
  end

  describe "show" do
    test "shows the CA's details", %{conn: conn, org: org} do
      %{db_cert: ca_cert} = Fixtures.ca_certificate_fixture(org)
      {:ok, ca_cert} = CACertificates.update_ca_certificate(ca_cert, %{description: "Factory signer"})

      conn
      |> visit("/org/#{org.name}/settings/certificates/#{ca_cert.serial}")
      |> assert_has("h1", text: "Factory signer")
      |> assert_has("a[href='/org/#{org.name}/settings/certificates']", text: "All Certificate Authorities")
      |> assert_has("code", text: Utils.format_serial(ca_cert.serial))
      |> assert_has("dd", text: "Never")
      |> assert_has("dd", text: "Disabled")
      |> assert_has("a", text: "Edit")
    end

    test "falls back to the serial when the CA has no description", %{conn: conn, org: org} do
      %{db_cert: %{serial: serial}} = Fixtures.ca_certificate_fixture(org)

      conn
      |> visit("/org/#{org.name}/settings/certificates/#{serial}")
      |> assert_has("h1", text: Utils.format_serial(serial))
    end

    test "shows the devices using the CA, linked to each product's filtered device list", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      %{db_cert: %{serial: serial}} = ca = Fixtures.ca_certificate_fixture(org)

      for _ <- 1..2 do
        device = Fixtures.device_fixture(org, product, firmware)
        Fixtures.device_certificate_fixture_for_ca(device, ca)
      end

      conn
      |> visit("/org/#{org.name}/settings/certificates/#{serial}")
      |> assert_has("#ca-devices", text: "Devices")
      |> assert_has("#ca-devices", text: product.name)
      |> assert_has("#ca-devices a[href='/org/#{org.name}/#{product.name}/devices?signer_ca=#{serial}']", text: "2")
    end

    test "says so when no devices are using the CA", %{conn: conn, org: org} do
      %{db_cert: %{serial: serial}} = Fixtures.ca_certificate_fixture(org)

      conn
      |> visit("/org/#{org.name}/settings/certificates/#{serial}")
      |> assert_has("#ca-devices", text: "No devices are using a certificate signed by this Certificate Authority.")
      |> refute_has("#ca-devices a")
    end

    test "is reachable from the list", %{conn: conn, org: org} do
      %{db_cert: %{serial: serial}} = Fixtures.ca_certificate_fixture(org)

      conn
      |> visit("/org/#{org.name}/settings/certificates")
      |> click_link("a[href='/org/#{org.name}/settings/certificates/#{serial}']", "")
      |> assert_path("/org/#{org.name}/settings/certificates/#{serial}")
    end

    test "redirects when the CA belongs to another org", %{conn: conn, org: org} do
      other_user = Fixtures.user_fixture()
      other_org = Fixtures.org_fixture(other_user, %{name: "someone-else"})
      %{db_cert: %{serial: serial}} = Fixtures.ca_certificate_fixture(other_org)

      conn
      |> visit("/org/#{org.name}/settings/certificates/#{serial}")
      |> assert_path("/org/#{org.name}/settings/certificates")
      |> assert_has("div", text: "Certificate Authority not found")
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
        # its a bit tricky to extract the registration code from the view,
        # so lets generate a new one and use that instead
        code = CSR.generate_verification_token(org)

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
      |> assert_has("tr > td > a > code")

      {:ok, ca} = File.read!(ca_file_path) |> X509.Certificate.from_pem()

      serial = Certificate.get_serial_number(ca)

      assert {:ok, %{description: ^description, serial: ^serial}} =
               CACertificates.get_ca_certificate_by_serial(serial)
    end

    test "renders errors when cert is invalid", %{conn: conn, org: org, tmp_dir: tmp_dir} do
      ca_file_path = Fixtures.device_certificate_authority_file()
      ca_key_file_path = Fixtures.device_certificate_authority_key_file()

      conn
      |> visit("/org/#{org.name}/settings/certificates/new")
      |> assert_has("h1", text: "New Certificate Authority")
      |> unwrap(fn view ->
        # its a bit tricky to extract the registration code from the view,
        # so lets generate a new one and use that instead
        code = CSR.generate_verification_token(org)

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

      assert [] = CACertificates.get_ca_certificates(org)
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
      |> assert_has("div", text: "The registration code in the verification certificate is not valid.")

      assert [] = CACertificates.get_ca_certificates(org)
    end

    test "creates a root CA without an AKI", %{conn: conn, org: org, tmp_dir: tmp_dir} do
      # Like the root LibreSSL's `openssl req -x509` makes from Step 1 on this page
      ca_cert = write_root_ca(tmp_dir, extensions: [authority_key_identifier: false])

      conn
      |> upload_root_ca(org, tmp_dir)
      |> click_button("Create Certificate")
      |> assert_path("/org/#{org.name}/settings/certificates")
      |> assert_has("div", text: "Certificate Authority created")

      assert {:ok, %{aki: nil}} = CACertificates.get_ca_certificate_by_serial(Certificate.get_serial_number(ca_cert))
    end

    test "creates a CA that has expired", %{conn: conn, org: org, tmp_dir: tmp_dir} do
      ca_cert = write_root_ca(tmp_dir, validity: @expired)

      conn
      |> upload_root_ca(org, tmp_dir)
      |> click_button("Create Certificate")
      |> assert_path("/org/#{org.name}/settings/certificates")
      |> assert_has("div",
        text:
          "Certificate Authority created. It expired on 2025-01-01. " <>
            "Devices can still register with it because Check expiration is off."
      )
      |> assert_has("td", text: "Expired")

      assert {:ok, %{not_after: ~U[2025-01-01 00:00:00Z], check_expiration: false}} =
               CACertificates.get_ca_certificate_by_serial(Certificate.get_serial_number(ca_cert))
    end

    test "creates a CA that isn't valid yet", %{conn: conn, org: org, tmp_dir: tmp_dir} do
      starts = DateTime.utc_now() |> DateTime.shift(day: 1) |> DateTime.truncate(:second)
      write_root_ca(tmp_dir, validity: Validity.new(starts, DateTime.shift(starts, year: 10)))

      conn
      |> upload_root_ca(org, tmp_dir)
      |> click_button("Create Certificate")
      |> assert_path("/org/#{org.name}/settings/certificates")
      |> assert_has("div",
        text:
          "Certificate Authority created. It isn't valid until #{Calendar.strftime(starts, "%Y-%m-%d %H:%M UTC")}. " <>
            "Devices can still register with it because Check expiration is off."
      )
      |> assert_has("td", text: "Not Yet Valid")
    end

    test "creates a CA not valid yet with Check expiration on", %{conn: conn, org: org, tmp_dir: tmp_dir} do
      starts = DateTime.utc_now() |> DateTime.shift(day: 1) |> DateTime.truncate(:second)
      write_root_ca(tmp_dir, validity: Validity.new(starts, DateTime.shift(starts, year: 10)))

      conn
      |> upload_root_ca(org, tmp_dir)
      |> check("Check expiration")
      |> click_button("Create Certificate")
      |> assert_has("div",
        text:
          "Certificate Authority created. It isn't valid until #{Calendar.strftime(starts, "%Y-%m-%d %H:%M UTC")}, " <>
            "and devices can't register with it until then."
      )
    end

    test "refuses an expired CA with Check expiration on", %{conn: conn, org: org, tmp_dir: tmp_dir} do
      write_root_ca(tmp_dir, validity: @expired)

      conn
      |> upload_root_ca(org, tmp_dir)
      |> check("Check expiration")
      |> click_button("Create Certificate")
      |> assert_path("/org/#{org.name}/settings/certificates/new")
      |> assert_has("span", text: "can't be on for a CA certificate that expired on 2025-01-01")

      assert [] = CACertificates.get_ca_certificates(org)
    end

    test "saves Check expiration", %{conn: conn, org: org, tmp_dir: tmp_dir} do
      ca_cert = write_root_ca(tmp_dir, [])

      conn
      |> upload_root_ca(org, tmp_dir)
      |> check("Check expiration")
      |> click_button("Create Certificate")
      |> assert_has("div", text: "Certificate Authority created")
      |> refute_has("div", text: "Certificate Authority created.")

      assert {:ok, %{check_expiration: true}} =
               CACertificates.get_ca_certificate_by_serial(Certificate.get_serial_number(ca_cert))
    end

    test "explains a CA without an SKI", %{conn: conn, org: org, tmp_dir: tmp_dir} do
      write_root_ca(tmp_dir, extensions: [subject_key_identifier: false])

      conn
      |> upload_root_ca(org, tmp_dir)
      |> click_button("Create Certificate")
      |> assert_path("/org/#{org.name}/settings/certificates/new")
      |> assert_has("#missing-ski-error", text: "no Subject Key Identifier extension")
      |> refute_has("div", text: "Something went wrong!")

      assert [] = CACertificates.get_ca_certificates(org)
    end

    test "renders error when no cert uploaded", %{conn: conn, org: org} do
      conn
      |> visit("/org/#{org.name}/settings/certificates/new")
      |> click_button("Create Certificate")
      |> assert_has("div", text: "Certificate Authority files required")
    end
  end

  describe "create with JITP" do
    test "creates CA with JITP", %{conn: conn, user: user, org: org, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)

      ca_file_path = Fixtures.device_certificate_authority_file()
      ca_key_file_path = Fixtures.device_certificate_authority_key_file()

      description = "My ca"

      conn
      |> visit("/org/#{org.name}/settings/certificates/new")
      |> assert_has("h1", text: "New Certificate Authority")
      |> unwrap(fn view ->
        # its a bit tricky to extract the registration code from the view,
        # so lets generate a new one and use that instead
        code = CSR.generate_verification_token(org)

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
      |> check("Enable Just In Time Provisioning", exact: false)
      |> fill_in("JITP Description", with: "a jitp description", exact: false)
      |> fill_in("JITP Tags", with: "prod", exact: false)
      |> select("JITP Product", option: product.name, exact: false)
      |> click_button("Create Certificate")
      |> assert_path("/org/#{org.name}/settings/certificates")
      |> assert_has("div", text: "Certificate Authority created")
      |> assert_has("h1", text: "Certificate Authorities")
      |> assert_has("tr > td > a > code")

      {:ok, ca} = File.read!(ca_file_path) |> X509.Certificate.from_pem()

      serial = Certificate.get_serial_number(ca)

      assert {:ok,
              %{
                description: ^description,
                serial: ^serial,
                jitp: %{tags: ["prod"], description: "a jitp description"}
              }} = CACertificates.get_ca_certificate_by_serial(serial)
    end
  end

  describe "delete" do
    test "deletes the certificate authority from its show page", %{conn: conn, org: org} do
      %{db_cert: ca} = Fixtures.ca_certificate_fixture(org)

      conn
      |> visit("/org/#{org.name}/settings/certificates/#{ca.serial}")
      |> click_button("Delete")
      |> assert_path("/org/#{org.name}/settings/certificates")
      |> assert_has("div", text: "Certificate successfully deleted")
      |> assert_has("h1", text: "Certificate Authorities")
      |> refute_has("code", text: Utils.format_serial(ca.serial))

      assert {:error, :not_found} = CACertificates.get_ca_certificate_by_serial(ca.serial)
    end

    test "shows error when delete fails", %{conn: conn, org: org} do
      %{db_cert: ca} = Fixtures.ca_certificate_fixture(org)

      stub(CACertificates, :delete_ca_certificate, fn _ ->
        {:error, :cannot_delete}
      end)

      conn
      |> visit("/org/#{org.name}/settings/certificates/#{ca.serial}")
      |> click_button("Delete")
      |> assert_has("div", text: "Failed to delete certificate. Please contact support if this happens again.")
    end

    test "the list no longer offers per-row edit and delete", %{conn: conn, org: org} do
      %{db_cert: ca} = Fixtures.ca_certificate_fixture(org)

      conn
      |> visit("/org/#{org.name}/settings/certificates")
      |> assert_has("code", text: Utils.format_serial(ca.serial))
      |> refute_has("tbody button")
      |> refute_has("a[href='/org/#{org.name}/settings/certificates/#{ca.serial}/edit']")
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
      |> assert_path("/org/#{org.name}/settings/certificates/#{serial}")
      |> assert_has("div", text: "Certificate Authority updated")

      assert {:ok, %{description: "a new description", serial: ^serial}} =
               CACertificates.get_ca_certificate_by_serial(serial)
    end

    test "keeps a JITP's tags apart when saved unchanged", %{conn: conn, user: user, org: org} do
      %{db_cert: db_cert} = Fixtures.ca_certificate_fixture(org)
      product = Fixtures.product_fixture(user, org)

      {:ok, _} =
        db_cert
        |> NervesHub.Repo.preload(:jitp)
        |> CACertificates.update_ca_certificate(%{
          jitp: %{tags: ["prod", "eu"], description: "a jitp description", product_id: product.id}
        })

      conn
      |> visit("/org/#{org.name}/settings/certificates/#{db_cert.serial}/edit")
      |> assert_has("#tag_input[value='prod, eu']")
      |> click_button("Update Certificate")
      |> assert_has("div", text: "Certificate Authority updated")

      assert {:ok, %{jitp: %{tags: ["prod", "eu"]}}} = CACertificates.get_ca_certificate_by_serial(db_cert.serial)
    end

    test "update fails when description is blank", %{conn: conn, user: user, org: org} do
      %{db_cert: %{serial: serial}} = Fixtures.ca_certificate_fixture(org)
      product = Fixtures.product_fixture(user, org)

      conn
      |> visit("/org/#{org.name}/settings/certificates/#{serial}/edit")
      |> assert_has("h1", text: "Edit Certificate Authority")
      |> check("Enable Just In Time Provisioning")
      |> fill_in("JITP Description", with: "", exact: false)
      |> fill_in("JITP Tags", with: "prod", exact: false)
      |> select("JITP Product", option: product.name, exact: false)
      |> click_button("Update Certificate")
      |> assert_path("/org/#{org.name}/settings/certificates/#{serial}/edit")
      |> assert_has("div", text: "Error updating certificate")
      |> assert_has("span", text: "can't be blank")
    end

    test "redirects when certificate not found on edit", %{conn: conn, org: org} do
      conn
      |> visit("/org/#{org.name}/settings/certificates/nonexistent-serial/edit")
      |> assert_path("/org/#{org.name}/settings/certificates")
      |> assert_has("div", text: "Certificate Authority not found")
    end

    test "redirects when the CA belongs to another org", %{conn: conn, org: org} do
      # CA serials are unique across the whole install, so a serial is a
      # guessable handle on someone else's CA unless the lookup is scoped.
      other_user = Fixtures.user_fixture()
      other_org = Fixtures.org_fixture(other_user, %{name: "someone-else"})
      %{db_cert: %{serial: serial}} = Fixtures.ca_certificate_fixture(other_org)

      conn
      |> visit("/org/#{org.name}/settings/certificates/#{serial}/edit")
      |> assert_path("/org/#{org.name}/settings/certificates")
      |> assert_has("div", text: "Certificate Authority not found")
    end

    test "does not update a CA belonging to another org", %{conn: conn, org: org} do
      %{db_cert: %{serial: serial}} = Fixtures.ca_certificate_fixture(org)

      other_user = Fixtures.user_fixture()
      other_org = Fixtures.org_fixture(other_user, %{name: "someone-else"})
      %{db_cert: other_ca} = Fixtures.ca_certificate_fixture(other_org)

      {:ok, view, _html} = live(conn, "/org/#{org.name}/settings/certificates/#{serial}/edit")

      # The edit page refuses to load another org's CA, so the serial the update
      # event is applied to never becomes one from another org.
      render_patch(view, "/org/#{org.name}/settings/certificates/#{other_ca.serial}/edit")

      render_submit(view, "update_certificate_authority", %{
        "ca_certificate" => %{"description" => "not yours"}
      })

      assert {:ok, %{description: nil}} =
               CACertificates.get_ca_certificate_by_org_and_serial(other_org, other_ca.serial)
    end
  end

  # Writes a P-256 root CA and its key to `rootCA.crt` and `rootCA.key` in `dir`
  defp write_root_ca(dir, opts) do
    ca_key = X509.PrivateKey.new_ec(:secp256r1)
    ca_cert = X509.Certificate.self_signed(ca_key, "CN=Root CA", Keyword.put(opts, :template, :root_ca))

    File.write!(Path.join(dir, "rootCA.key"), X509.PrivateKey.to_pem(ca_key))
    File.write!(Path.join(dir, "rootCA.crt"), X509.Certificate.to_pem(ca_cert))

    ca_cert
  end

  # Opens the new CA page and uploads the root CA from `write_root_ca/2`, with a
  # verification certificate it signed
  defp upload_root_ca(conn, org, dir) do
    ca_file_path = Path.join(dir, "rootCA.crt")

    conn
    |> visit("/org/#{org.name}/settings/certificates/new")
    |> unwrap(fn view ->
      code = CSR.generate_verification_token(org)

      %{verification_cert_crt: verification_cert_crt} =
        Fixtures.generate_certificate_authority_csr(ca_file_path, Path.join(dir, "rootCA.key"), code, dir)

      upload_file(view, "rootCA.crt", ca_file_path, :cert)
      upload_file(view, "verificationCert.crt", verification_cert_crt, :csr)
    end)
  end

  defp upload_file(view, file_name, file_path, form_field) do
    csr =
      file_input(view, "#new-ca-form", form_field, [
        %{
          last_modified: 1_594_171_879_000,
          name: file_name,
          content: File.read!(file_path)
        }
      ])

    render_upload(csr, file_name)
  end
end

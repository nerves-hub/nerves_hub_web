defmodule NervesHubWWWWeb.OrgCertificateControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: true

  alias NervesHubWebCore.{Certificate, Devices, Fixtures}

  describe "index" do
    test "lists all appropriate device(ca) certificates", %{
      conn: conn,
      org: org
    } do
      %{db_cert: db1_cert} = Fixtures.ca_certificate_fixture(org)
      %{db_cert: db2_cert} = Fixtures.ca_certificate_fixture(org)

      conn = get(conn, Routes.org_certificate_path(conn, :index, org.name))
      assert html_response(conn, 200) =~ "Certificate Authorities"
      assert html_response(conn, 200) =~ db1_cert.serial
      assert html_response(conn, 200) =~ db2_cert.serial
    end
  end

  describe "new" do
    test "renders form", %{conn: conn, org: org} do
      conn = get(conn, Routes.org_certificate_path(conn, :new, org.name))
      assert html_response(conn, 200) =~ "New Certificate Authority"
    end
  end

  describe "create" do
    test "CA is created on success", %{conn: conn, org: org} do
      ca_file_path = Fixtures.device_certificate_authority_file()
      {:ok, ca} = File.read!(ca_file_path) |> X509.Certificate.from_pem()
      serial = Certificate.get_serial_number(ca)
      description = "My ca"

      upload = %Plug.Upload{
        path: ca_file_path
      }

      params = %{ca_certificate: %{cert: upload, description: description}}

      conn = post(conn, Routes.org_certificate_path(conn, :create, org.name), params)
      assert redirected_to(conn) == Routes.org_certificate_path(conn, :index, org.name)

      assert {:ok, %{description: ^description, serial: ^serial}} =
               Devices.get_ca_certificate_by_serial(serial)
    end

    test "renders errors when cert is invalid", %{conn: conn, org: org} do
      bad_ca_file_path = Fixtures.bad_device_certificate_authority_file()

      upload = %Plug.Upload{
        path: bad_ca_file_path
      }

      params = %{ca_certificate: %{cert: upload}}

      conn = post(conn, Routes.org_certificate_path(conn, :create, org.name), params)
      assert redirected_to(conn) == Routes.org_certificate_path(conn, :new, org.name)
      conn = get(conn, Routes.org_certificate_path(conn, :new, org.name))
      assert html_response(conn, 200) =~ "Error decoding certificate"
    end

    test "renders errors when params are invalid", %{conn: conn, org: org} do
      ca_file_path = Fixtures.device_certificate_authority_file()
      {:ok, ca} = File.read!(ca_file_path) |> X509.Certificate.from_pem()
      serial = Certificate.get_serial_number(ca)
      description = 123

      upload = %Plug.Upload{
        path: ca_file_path
      }

      params = %{ca_certificate: %{cert: upload, description: description}}

      conn = post(conn, Routes.org_certificate_path(conn, :create, org.name), params)
      assert html_response(conn, 200) =~ "Error creating certificate"

      assert {:error, :not_found} = Devices.get_ca_certificate_by_serial(serial)
    end
  end

  describe "edit" do
    test "renders form", %{conn: conn, org: org} do
      %{db_cert: ca} = Fixtures.ca_certificate_fixture(org)
      conn = get(conn, Routes.org_certificate_path(conn, :edit, org.name, ca.serial))
      assert html_response(conn, 200) =~ "Edit Certificate Authority"
    end

    test "redirects to index when not found", %{conn: conn, org: org} do
      conn = get(conn, Routes.org_certificate_path(conn, :edit, org.name, "unknown-serial"))
      assert redirected_to(conn, 302) =~ Routes.org_certificate_path(conn, :index, org.name)
    end
  end

  describe "update" do
    test "CA is updated on success", %{conn: conn, org: org} do
      %{db_cert: %{serial: serial}} = Fixtures.ca_certificate_fixture(org)
      params = %{ca_certificate: %{description: "test"}}
      conn = put(conn, Routes.org_certificate_path(conn, :update, org.name, serial), params)
      assert redirected_to(conn) == Routes.org_certificate_path(conn, :index, org.name)

      assert {:ok, %{description: "test", serial: ^serial}} =
               Devices.get_ca_certificate_by_serial(serial)
    end

    test "updated fails when ca not found", %{conn: conn, org: org} do
      conn =
        put(conn, Routes.org_certificate_path(conn, :update, org.name, "unknown-serial"), %{
          ca_certificate: %{}
        })

      assert redirected_to(conn) == Routes.org_certificate_path(conn, :index, org.name)
    end
  end

  describe "delete certificate authority" do
    test "deletes chosen resource", %{
      conn: conn,
      org: org
    } do
      %{db_cert: ca} = Fixtures.ca_certificate_fixture(org)

      conn =
        delete(
          conn,
          Routes.org_certificate_path(conn, :delete, org.name, ca.serial)
        )

      assert redirected_to(conn) == Routes.org_certificate_path(conn, :index, org.name)

      assert Devices.get_ca_certificate_by_serial(ca.serial) ==
               {:error, :not_found}
    end
  end
end

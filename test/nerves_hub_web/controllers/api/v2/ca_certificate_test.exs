defmodule NervesHubWeb.API.V2.CACertificateTest do
  use NervesHubWeb.AshAPIConnCase, async: false

  alias NervesHub.Fixtures

  setup %{org: org} do
    %{db_cert: ca_cert} = Fixtures.ca_certificate_fixture(org)

    [ca_cert: ca_cert]
  end

  describe "index" do
    test "lists CA certificates", %{conn: conn} do
      conn = get(conn, "/api/v2/ca-certificates")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      assert length(resp["data"]) >= 1
    end
  end

  describe "show" do
    test "returns a CA certificate", %{conn: conn, ca_cert: ca_cert} do
      conn = get(conn, "/api/v2/ca-certificates/#{ca_cert.id}")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["serial"] == ca_cert.serial
    end
  end

  describe "list_by_org" do
    test "lists CA certificates by org", %{conn: conn, org: org, ca_cert: ca_cert} do
      conn = get(conn, "/api/v2/ca-certificates/by-org/#{org.id}")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      serials = Enum.map(resp["data"], & &1["attributes"]["serial"])
      assert ca_cert.serial in serials
    end
  end

  describe "get_by_org_and_serial" do
    test "returns a CA cert by org and serial", %{conn: conn, org: org, ca_cert: ca_cert} do
      conn = get(conn, "/api/v2/ca-certificates/by-org/#{org.id}/serial/#{ca_cert.serial}")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["serial"] == ca_cert.serial
    end
  end

  describe "delete" do
    test "deletes a CA certificate", %{conn: conn, ca_cert: ca_cert} do
      conn = delete(conn, "/api/v2/ca-certificates/#{ca_cert.id}")
      assert response(conn, 200)
    end
  end
end

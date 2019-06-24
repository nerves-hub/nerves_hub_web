defmodule NervesHubWWWWeb.OrgCertificateControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: true

  alias NervesHubWebCore.Fixtures

  describe "index" do
    test "lists all appropriate device(ca) certificates", %{
      conn: conn,
      org: org
    } do
      %{db_cert: db1_cert} = Fixtures.ca_certificate_fixture(org)
      %{db_cert: db2_cert} = Fixtures.ca_certificate_fixture(org)

      conn = get(conn, org_certificate_path(conn, :index, org.name))
      assert html_response(conn, 200) =~ "#{org.name} Device (CA) Certificates"
      assert html_response(conn, 200) =~ db1_cert.serial
      assert html_response(conn, 200) =~ db2_cert.serial
    end
  end
end

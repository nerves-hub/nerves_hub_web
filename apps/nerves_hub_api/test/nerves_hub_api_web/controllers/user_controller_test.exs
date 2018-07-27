defmodule NervesHubAPIWeb.UserControllerTest do
  use NervesHubAPIWeb.ConnCase

  alias NervesHubCore.Fixtures

  @certificate Path.join([__DIR__, "../../../../../test/fixtures/cfssl/user.pem"])

  setup %{conn: conn} do
    certificate = File.read!(@certificate)
    [{:Certificate, certificate, _}] = :public_key.pem_decode(certificate)
    
    conn = 
      conn
      |> put_req_header("accept", "application/json")
      |> Plug.Test.put_peer_data(%{address: {127, 0, 0, 1}, port: 111_317, ssl_cert: certificate})

    user = 
      Fixtures.tenant_fixture()
      |> Fixtures.user_fixture()

    {:ok, conn: conn, user: user}
  end

  test "me", %{conn: conn, user: user} do
    Plug.Conn.get_peer_data(conn)
    conn = get conn, user_path(conn, :me)
    assert json_response(conn, 200)["data"] == %{
      "name" => user.name,
      "email" => user.email
    }
  end
end

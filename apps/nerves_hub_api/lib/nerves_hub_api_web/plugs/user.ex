defmodule NervesHubAPIWeb.Plugs.User do
  import Plug.Conn

  alias NervesHubCore.{Accounts, Certificate}
  alias NervesHubCore.Accounts.User
  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    conn
    |> Plug.Conn.get_peer_data()
    |> Map.get(:ssl_cert)
    |> case do
      nil -> nil
      cert -> 
        cert = 
          {:Certificate, cert, :not_encrypted}
          |> List.wrap()
          |> :public_key.pem_encode()
        {:ok, serial} = Certificate.get_serial_number(cert)
        Accounts.get_user_with_certificate_serial(serial)
    end
    |> case do
      nil ->
        conn
        |> put_resp_header("content-type", "application/json")
        |> send_resp(403, Jason.encode!(%{status: "forbidden"}))
        |> halt()

      %User{} = user ->
        user = NervesHubCore.Repo.preload(user, [tenant: [:tenant_keys]])
        conn
        |> assign(:user, user)
        |> assign(:tenant, user.tenant)

    end
  end
end

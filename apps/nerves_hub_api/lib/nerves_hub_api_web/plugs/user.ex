defmodule NervesHubAPIWeb.Plugs.User do
  import Plug.Conn

  alias NervesHubWebCore.{Accounts, Certificate}
  alias NervesHubWebCore.Accounts.User

  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    conn
    |> Plug.Conn.get_peer_data()
    |> Map.get(:ssl_cert)
    |> case do
      nil ->
        nil

      cert ->
        cert = X509.Certificate.from_der!(cert)
        serial = Certificate.get_serial_number(cert)
        Accounts.get_user_certificate_by_serial(serial)
    end
    |> case do
      {:ok, %{user: user} = cert} ->
        Accounts.update_user_certificate(cert, %{last_used: DateTime.utc_now()})
        user = User.with_default_org(user)

        conn
        |> assign(:user, user)

      _error ->
        conn
        |> put_resp_header("content-type", "application/json")
        |> send_resp(403, Jason.encode!(%{status: "forbidden"}))
        |> halt()
    end
  end
end

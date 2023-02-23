defmodule NervesHubWeb.API.Plugs.User do
  import Plug.Conn

  alias NervesHub.{Accounts, Certificate}

  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    case authenticate_user(conn) do
      {:ok, %{user: user} = auth} ->
        _ = mark_last_used(auth)

        assign(conn, :user, user)

      _error ->
        conn
        |> put_resp_header("content-type", "application/json")
        |> send_resp(403, Jason.encode!(%{status: "forbidden"}))
        |> halt()
    end
  end

  defp authenticate_user(conn) do
    # Prefer token authentication as the default
    # Support legacy peer certificate auth for backwards compatibility
    case get_req_token(conn) do
      {:ok, token} ->
        token_auth(token)

      _ ->
        peer_cert_auth(conn)
    end
  end

  defp get_req_token(conn) do
    with [header] <- get_req_header(conn, "authorization"),
         [scheme, token | _] = String.split(header, " "),
         true <- String.downcase(scheme) in ["token", "bearer"] do
      {:ok, token}
    end
  end

  defp token_auth(<<"nh", _u, "_", hmac::30-bytes, crc_bin::6-bytes>> = token) do
    with {:ok, crc} <- Base62.decode(crc_bin),
         true <- :erlang.crc32(hmac) == crc do
      Accounts.get_user_token(token)
    end
  end

  defp token_auth(_token), do: :forbidden

  defp peer_cert_auth(conn) do
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
  end

  defp mark_last_used(record) do
    Ecto.Changeset.change(record, %{last_used: DateTime.truncate(DateTime.utc_now(), :second)})
    |> NervesHub.Repo.update()
  end
end

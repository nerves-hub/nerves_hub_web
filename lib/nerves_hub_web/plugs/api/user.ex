defmodule NervesHubWeb.API.Plugs.User do
  import Plug.Conn

  alias NervesHub.Accounts

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
        :error
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

  defp mark_last_used(record) do
    Ecto.Changeset.change(record, %{last_used: DateTime.truncate(DateTime.utc_now(), :second)})
    |> NervesHub.Repo.update()
  end
end

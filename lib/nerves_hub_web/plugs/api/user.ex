defmodule NervesHubWeb.API.Plugs.User do
  import Plug.Conn

  alias NervesHub.Accounts

  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    case authenticate_user(conn) do
      {:ok, user} ->
        _ = mark_last_used(conn)

        assign(conn, :user, user)

      _error ->
        raise NervesHubWeb.UnauthorizedError
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

  defp token_auth(<<"nh", _u, "_", token::43-bytes>>) do
    Accounts.fetch_user_by_api_token(token)
  end

  defp token_auth(_token) do
    :forbidden
  end

  defp mark_last_used(conn) do
    with [header] <- get_req_header(conn, "authorization"),
         [scheme, full_token | _] = String.split(header, " "),
         true <- String.downcase(scheme) in ["token", "bearer"],
         <<"nh", _u, "_", token::43-bytes>> <- full_token do
      Accounts.mark_last_used(token)
    end
  end
end

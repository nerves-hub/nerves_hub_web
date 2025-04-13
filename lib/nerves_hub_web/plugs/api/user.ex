defmodule NervesHubWeb.API.Plugs.AuthenticateUser do
  import Plug.Conn

  alias NervesHub.Accounts

  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    with {:ok, token} <- get_req_token(conn),
         {:ok, user, user_token} <- Accounts.fetch_user_by_api_token(token),
         :ok <- Accounts.mark_last_used(user_token) do
      assign(conn, :user, user)
    else
      _ ->
        raise NervesHubWeb.UnauthorizedError
    end
  end

  defp get_req_token(conn) do
    with [header] <- get_req_header(conn, "authorization"),
         [scheme, token | _] = String.split(header, " "),
         true <- String.downcase(scheme) in ["token", "bearer"] do
      {:ok, token}
    end
  end
end

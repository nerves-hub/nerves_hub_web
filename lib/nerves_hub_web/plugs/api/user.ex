defmodule NervesHubWeb.API.Plugs.AuthenticateUserOrProduct do
  import Plug.Conn

  alias NervesHub.Accounts
  alias NervesHub.Products

  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    case get_req_token(conn) do
      {:ok, "nhp_api_" <> _ = product_api_key} ->
        handle_product_key(conn, product_api_key)

      {:ok, user_token} ->
        handle_user_token(conn, user_token)

      _ ->
        raise NervesHubWeb.UnauthorizedError
    end
  end

  defp get_req_token(conn) do
    with [header] <- get_req_header(conn, "authorization"),
         {scheme, token} <- get_scheme_and_token(header),
         true <- String.downcase(scheme) in ["token", "bearer"] do
      {:ok, token}
    end
  end

  def handle_product_key(conn, key) do
    case Products.get_product_by_api_key(key) do
      {:ok, product} ->
        conn
        |> assign(:auth_type, :product_api_key)
        |> assign(:product, product)
        |> assign(:org, product.org)
        # A lot of code excepts a user value, get rid of this with time
        |> assign(:user, product)

      _ ->
        raise NervesHubWeb.UnauthorizedError
    end
  end

  def handle_user_token(conn, token) do
    with {:ok, user, user_token} <- Accounts.fetch_user_by_api_token(token),
         :ok <- Accounts.mark_last_used(user_token) do
      conn
      |> assign(:auth_type, :user_token)
      |> assign(:user, user)
    else
      _ ->
        raise NervesHubWeb.UnauthorizedError
    end
  end

  defp get_scheme_and_token(header) do
    case String.split(header, " ") do
      [scheme, token | _] ->
        {scheme, token}

      _ ->
        :invalid_token_format
    end
  end
end

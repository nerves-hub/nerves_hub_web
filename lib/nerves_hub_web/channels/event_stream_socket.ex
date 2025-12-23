defmodule NervesHubWeb.EventStreamSocket do
  use Phoenix.Socket

  alias NervesHub.Accounts
  alias NervesHub.Products

  channel("device:*", NervesHubWeb.DeviceEventsStreamChannel)

  @impl Phoenix.Socket
  def connect(params, socket, _connect_info) do
    case get_token(params) do
      {:ok, "nhp_api_" <> _ = product_api_key} ->
        handle_product_key(socket, product_api_key)

      {:ok, user_token} ->
        handle_user_token(socket, user_token)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_product_key(socket, key) do
    case Products.get_product_by_api_key(key) do
      {:ok, product} ->
        socket =
          socket
          |> assign(:auth_type, :product_api_key)
          |> assign(:product, product)
          |> assign(:org, product.org)

        {:ok, socket}

      _ ->
        {:error, :authorization_failed}
    end
  end

  # We want to deprecate the user token for websocket access
  defp handle_user_token(socket, token) do
    with {:ok, user} <- fetch_user(token) do
      socket =
        socket
        |> assign(:auth_type, :user_token)
        |> assign(:user, user)

      {:ok, socket}
    end
  end

  @impl Phoenix.Socket
  def id(_socket), do: nil

  defp get_token(params) do
    case Map.get(params, "token") do
      token when is_binary(token) and byte_size(token) > 0 ->
        {:ok, token}

      nil ->
        {:error, :no_token}

      _ ->
        {:error, :invalid_token}
    end
  end

  defp fetch_user(token) do
    case Accounts.fetch_user_by_api_token(token) do
      {:ok, user, user_token} ->
        :ok = Accounts.mark_last_used(user_token)

        {:ok, user}

      _ ->
        {:error, :invalid_token}
    end
  end
end

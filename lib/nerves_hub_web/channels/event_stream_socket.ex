defmodule NervesHubWeb.EventStreamSocket do
  use Phoenix.Socket

  alias NervesHub.Accounts.Scope
  alias NervesHub.Products.ApiKey
  alias NervesHub.Products.ApiKeys
  alias NervesHubWeb.Auth

  channel("device:*", NervesHubWeb.DeviceEventsStreamChannel)

  @impl Phoenix.Socket
  def connect(params, socket, _connect_info) do
    with {:ok, token} <- get_token(params),
         {:ok, scope} <- fetch_scope(token) do
      {:ok, assign(socket, :current_scope, scope)}
    end
  end

  # A socket opened with a product API key gets an id, so deactivating the key
  # or editing its custom role disconnects it. A socket only authenticates on
  # connect, where an API request does so every time.
  @impl Phoenix.Socket
  def id(%{assigns: %{current_scope: %Scope{api_key: %ApiKey{} = api_key}}}), do: ApiKeys.socket_id(api_key)
  def id(_socket), do: nil

  defp get_token(params) do
    case Map.get(params, "token") do
      token when is_binary(token) and byte_size(token) > 0 ->
        {:ok, token}

      _ ->
        {:error, :no_token}
    end
  end

  # Either a user API token or a product API key.
  defp fetch_scope(token) do
    case Auth.fetch_api_scope(token) do
      {:ok, scope} -> {:ok, scope}
      :error -> {:error, :invalid_token}
    end
  end
end

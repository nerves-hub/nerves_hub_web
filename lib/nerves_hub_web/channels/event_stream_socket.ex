defmodule NervesHubWeb.EventStreamSocket do
  use Phoenix.Socket

  alias NervesHub.Accounts

  channel("device:*", NervesHubWeb.DeviceEventsStreamChannel)

  @impl Phoenix.Socket
  def connect(params, socket, _connect_info) do
    with {:ok, token} <- get_token(params),
         {:ok, user} <- fetch_user(token) do
      {:ok, assign(socket, :user, user)}
    end
  end

  @impl Phoenix.Socket
  def id(_socket), do: nil

  defp get_token(params) do
    case Map.get(params, "token") do
      token when is_binary(token) and byte_size(token) > 0 ->
        {:ok, token}

      _ ->
        {:error, :no_token}
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

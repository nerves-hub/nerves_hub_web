defmodule NervesHubWeb.APISocket do
  use Phoenix.Socket

  alias NervesHub.Accounts

  channel("device:*", NervesHubWeb.ExternalDeviceListenerChannel)

  @impl Phoenix.Socket
  def connect(params, socket) do
    case params do
      %{"token" => token} when is_binary(token) ->
        # Authenticate user and store in socket assigns
        case Accounts.fetch_user_by_api_token(token) do
          {:ok, user, user_token} ->
            :ok = Accounts.mark_last_used(user_token)

            {:ok, assign(socket, :user, user)}

          _ ->
            {:error, :invalid_token}
        end

      _ ->
        {:error, :no_token}
    end
  end

  @impl Phoenix.Socket
  def id(_socket), do: nil
end

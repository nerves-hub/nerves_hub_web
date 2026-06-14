defmodule NervesHubWeb.UserSocket do
  use Phoenix.Socket

  alias NervesHub.Accounts

  channel("user:console:*", NervesHubWeb.UserConsoleChannel)
  channel("user:local_shell:*", NervesHubWeb.UserLocalShellChannel)

  def connect(%{"token" => token}, socket) do
    authenticate(socket, token)
    |> case do
      {:ok, user} ->
        socket = assign(socket, :user, user)
        {:ok, socket}

      {:error, _} ->
        :error
    end
  end

  def connect(_, _socket) do
    :error
  end

  def id(%{assigns: %{user: user}}) do
    "user_socket:#{user.id}"
  end

  def id(_socket) do
    nil
  end

  defp authenticate(_socket, "nhu_" <> _ = token) do
    with {:ok, user, user_token} <- Accounts.fetch_user_by_api_token(token),
         :ok <- Accounts.mark_last_used(user_token) do
      {:ok, user}
    else
      _ -> {:error, :invalid_token}
    end
  end

  defp authenticate(socket, token) do
    with {:ok, user_id} <- Phoenix.Token.verify(socket, "user salt", token, max_age: 86_400),
         {:ok, user} <- Accounts.get_user(user_id) do
      {:ok, user}
    else
      _ -> {:error, :invalid_token}
    end
  end
end

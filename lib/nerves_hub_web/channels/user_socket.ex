defmodule NervesHubWeb.UserSocket do
  use Phoenix.Socket

  alias NervesHub.Accounts

  channel("user:console:*", NervesHubWeb.UserConsoleChannel)
  channel("user:local_shell:*", NervesHubWeb.UserLocalShellChannel)

  def connect(%{"api_token" => api_token}, socket) do
    with {:ok, user, user_token} <- Accounts.fetch_user_by_api_token(api_token),
         :ok <- Accounts.mark_last_used(user_token) do
      {:ok, assign(socket, :user, user)}
    else
      _ -> :error
    end
  end

  def connect(%{"session_token" => session_token}, socket) do
    with {:ok, decoded} <- Base.url_decode64(session_token),
         %NervesHub.Accounts.User{} = user <- Accounts.get_user_by_session_token(decoded) do
      {:ok, assign(socket, :user, user)}
    else
      _ -> :error
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
end

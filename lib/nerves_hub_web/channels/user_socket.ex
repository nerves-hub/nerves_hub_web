defmodule NervesHubWeb.UserSocket do
  use Phoenix.Socket

  alias NervesHub.Accounts

  channel("user:console:*", NervesHubWeb.UserConsoleChannel)
  channel("user:local_shell:*", NervesHubWeb.UserLocalShellChannel)

  def connect(%{"token" => token}, socket) do
    case Phoenix.Token.verify(socket, "user salt", token, max_age: 86_400) do
      {:ok, user_id} ->
        case Accounts.get_user(user_id) do
          {:ok, user} ->
            socket = assign(socket, :user, user)
            {:ok, socket}

          {:error, _} ->
            :error
        end

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
end

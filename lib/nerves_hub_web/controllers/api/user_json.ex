defmodule NervesHubWeb.API.UserJSON do
  @moduledoc false

  def show(%{token: token, user: user}) do
    data =
      user(user)
      |> Map.put(:token, token)

    %{data: data}
  end

  def show(%{user: user}) do
    %{data: user(user)}
  end

  defp user(user) do
    %{email: user.email, name: user.name}
  end
end

defmodule NervesHubWeb.API.UserJSON do
  @moduledoc false

  def show(%{user: user, token: token}) do
    data =
      user(user)
      |> Map.put(:token, token)

    %{data: data}
  end

  def show(%{user: user}) do
    %{data: user(user)}
  end

  def console_token(%{token: token}) do
    %{data: %{token: token}}
  end

  defp user(user) do
    %{name: user.name, email: user.email}
  end
end

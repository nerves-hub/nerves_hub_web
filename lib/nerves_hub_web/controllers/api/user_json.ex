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

  def cli_session(%{token: token, url: url}) do
    %{data: %{token: token, url: url}}
  end

  def check_cli_session(%{status: :ready, user_token: user_token}) do
    %{data: %{status: :ready, user_token: user_token}}
  end

  def check_cli_session(%{status: :waiting}) do
    %{data: %{status: :waiting}}
  end

  defp user(user) do
    %{name: user.name, email: user.email}
  end
end

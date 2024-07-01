defmodule NervesHubWeb.API.UserView do
  use NervesHubWeb, :api_view

  alias NervesHubWeb.API.UserView

  def render("show.json", %{user: user, token: token}) do
    data =
      render_one(user, UserView, "user.json")
      |> Map.put(:token, token)

    %{data: data}
  end

  def render("show.json", %{user: user}) do
    %{data: render_one(user, UserView, "user.json")}
  end

  def render("user.json", %{user: user}) do
    %{name: user.name, email: user.email}
  end

  def render("cert.json", %{cert: cert}) do
    %{data: %{cert: cert}}
  end
end

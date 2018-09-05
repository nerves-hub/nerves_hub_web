defmodule NervesHubAPIWeb.UserView do
  use NervesHubAPIWeb, :view
  alias NervesHubAPIWeb.UserView

  def render("show.json", %{user: user}) do
    %{data: render_one(user, UserView, "user.json")}
  end

  def render("user.json", %{user: user}) do
    %{username: user.username, email: user.email}
  end

  def render("cert.json", %{cert: cert}) do
    %{data: %{cert: cert}}
  end
end

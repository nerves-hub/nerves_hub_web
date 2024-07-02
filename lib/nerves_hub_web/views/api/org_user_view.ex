defmodule NervesHubWeb.API.OrgUserView do
  use NervesHubWeb, :api_view

  alias NervesHubWeb.API.OrgUserView

  def render("index.json", %{org_users: org_users}) do
    %{data: render_many(org_users, OrgUserView, "org_user.json")}
  end

  def render("show.json", %{org_user: org_user}) do
    %{data: render_one(org_user, OrgUserView, "org_user.json")}
  end

  def render("org_user.json", %{org_user: org_user}) do
    %{
      name: org_user.user.name,
      email: org_user.user.email,
      role: org_user.role
    }
  end
end

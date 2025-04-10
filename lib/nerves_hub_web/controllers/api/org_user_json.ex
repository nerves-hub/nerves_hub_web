defmodule NervesHubWeb.API.OrgUserJSON do
  @moduledoc false

  def index(%{org_users: org_users}) do
    %{data: for(org_user <- org_users, do: org_user(org_user))}
  end

  def show(%{org_user: org_user}) do
    %{data: org_user(org_user)}
  end

  defp org_user(org_user) do
    %{
      name: org_user.user.name,
      email: org_user.user.email,
      role: org_user.role
    }
  end
end

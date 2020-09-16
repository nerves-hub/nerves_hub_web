defmodule NervesHubWWWWeb.OrgUserView do
  use NervesHubWWWWeb, :view

  alias NervesHubWebCore.Accounts.User

  def role_options() do
    User.Role.__enum_map__() |> Enum.map(fn opt -> {format_option(opt), opt} end)
  end

  defp format_option(opt) do
    opt
    |> to_string()
    |> String.capitalize()
  end
end

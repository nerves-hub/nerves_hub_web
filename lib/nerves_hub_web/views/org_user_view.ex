defmodule NervesHubWeb.OrgUserView do
  use NervesHubWeb, :view

  alias NervesHub.Accounts.User

  def role_options() do
    User.Role.__enum_map__() |> Enum.map(fn opt -> {format_option(opt), opt} end)
  end

  defp format_option(opt) do
    opt
    |> to_string()
    |> String.capitalize()
  end
end

defmodule NervesHubWeb.OrgUserView do
  use NervesHubWeb, :view

  alias NervesHub.Accounts.OrgUser

  def role_options() do
    OrgUser
    |> Ecto.Enum.mappings(:role)
    |> Enum.map(fn {key, value} -> {format_option(value), key} end)
  end

  defp format_option(opt) do
    opt
    |> to_string()
    |> String.capitalize()
  end
end

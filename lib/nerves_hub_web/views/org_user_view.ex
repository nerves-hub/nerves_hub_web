defmodule NervesHubWeb.OrgUserView do
  use NervesHubWeb, :view

  alias NervesHub.Accounts.OrgUser

  def role_options() do
    Enum.map(Ecto.Enum.values(OrgUser, :role), fn opt ->
      {format_option(opt), opt}
    end)
  end

  defp format_option(opt) do
    opt
    |> to_string()
    |> String.capitalize()
  end
end

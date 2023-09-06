defmodule NervesHubWeb.OrgUserView do
  use NervesHubWeb, :view

  alias NervesHub.Accounts.OrgUser

  def role_options() do
    for {key, value} <- Ecto.Enum.mappings(OrgUser, :role),
        key in [:admin, :read],
        do: {String.capitalize(value), key}
  end
end

defmodule NervesHub.Helpers.Authorization do
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.User

  def authorized!(org_user, permission) do
    true = authorized?(org_user, permission)
  end

  def authorized?(:update_product, %OrgUser{role: user_role}), do: role_check(:write, user_role)
  def authorized?(:delete_product, %OrgUser{role: user_role}), do: role_check(:admin, user_role)

  defp role_check(required_role, user_role) do
    required_role
    |> User.role_or_higher()
    |> Enum.any?(&(&1 == user_role))
  end
end

# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     NervesHub.Repo.insert!(%NervesHub.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# The seeds are run on every deploy. Therefore, it is important
# that first check to see if the data you are trying to insert
# has been run yet.

alias NervesHubCore.{Repo, Accounts}
alias NervesHubCore.Accounts.{Tenant, User}

# Create the root tenant
root_tenant_name = "nerves-hub"

root_tenant =
  if root_tenant = Repo.get_by(Tenant, name: root_tenant_name) do
    root_tenant
  else
    {:ok, root_tenant} = Accounts.create_tenant(%{name: root_tenant_name})
    root_tenant
  end

# Add a default user
root_user_email = "nerveshub@nerves-hub.org"

if root_user = Repo.get_by(User, email: root_user_email) do
  root_user
else
  Accounts.create_user(root_tenant, %{
    name: "nerveshub",
    email: root_user_email,
    password: "nerveshub"
  })
end

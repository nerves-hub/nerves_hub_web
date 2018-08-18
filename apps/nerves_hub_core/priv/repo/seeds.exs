# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     NervesHubCore.Repo.insert!(%NervesHubWWW.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# The seeds are run on every deploy. Therefore, it is important
# that first check to see if the data you are trying to insert
# has been run yet.

alias NervesHubCore.{Repo, Accounts}
alias NervesHubCore.Accounts.{Org, User}

# Create the root org and user
root_user_name = "nerveshub"
root_user_email = "nerveshub@nerves-hub.org"

root_org =
  if root_org = Repo.get_by(Org, name: root_user_name) do
    root_org
  else
    {:ok, root_org} = Accounts.create_org(%{name: root_user_name})
    root_org
  end

# Add a default user
if root_user = Repo.get_by(User, email: root_user_email) do
  root_user
else
  Accounts.create_user(root_org, %{
    name: root_user_name,
    email: root_user_email,
    password: "nerveshub"
  })
end

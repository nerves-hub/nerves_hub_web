defmodule NervesHubCore.Repo.Migrations.AssociateUsersAndOrgs do
  use Ecto.Migration

  import Ecto.Changeset

  alias NervesHubCore.Repo
  alias NervesHubCore.Accounts
  alias NervesHubCore.Accounts.{User, Org}

  def up do
    users = Repo.all(User)
    for user <- users do
      user = Repo.preload(user, :orgs)
      org = Repo.get_by!(Org, name: user.name)
      unless org in user.orgs do
        orgs = [org | user.orgs]
        Accounts.change_user(user, %{})
        |> put_assoc(:orgs, orgs)
        |> Repo.update!
      end
    end
  end

  # There is no going back
  def down do
    
  end
end

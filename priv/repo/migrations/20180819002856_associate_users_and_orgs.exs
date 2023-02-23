defmodule NervesHub.Repo.Migrations.AssociateUsersAndOrgs do
  use Ecto.Migration

  # import Ecto.Changeset

  # alias NervesHub.Repo
  # alias NervesHub.Accounts
  # alias NervesHub.Accounts.{User, Org}

  def up do
    # This should have been done outside of a migration. If the User schema ever changes then
    # executing this migration will fail. Prod will never run it again and it has no impact on
    # fresh dev/test databases.
    #
    # users = Repo.all(User)
    # for user <- users do
    #   user = Repo.preload(user, :orgs)
    #   org = Repo.get_by!(Org, name: user.name)
    #   unless org in user.orgs do
    #     orgs = [org | user.orgs]
    #     Accounts.change_user(user, %{})
    #     |> put_assoc(:orgs, orgs)
    #     |> Repo.update!
    #   end
    # end
  end

  # There is no going back
  def down do
  end
end

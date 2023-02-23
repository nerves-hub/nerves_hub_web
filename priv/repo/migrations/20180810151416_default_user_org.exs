defmodule NervesHub.Repo.Migrations.DefaultUserOrg do
  # import Ecto.Query
  use Ecto.Migration

  # alias NervesHub.Accounts
  # alias NervesHub.Accounts.{User, Org}
  # alias NervesHub.Repo

  def up do
    # This should have been done outside of a migration. If the User schema ever changes then
    # executing this migration will fail. Prod will never run it again and it has no impact on
    # fresh dev/test databases.
    #
    # new_org_ids =
    #   from(u in User)
    #   |> Repo.all()
    #   |> Enum.map(fn u ->
    #     {:ok, org} = Accounts.create_org(%{name: u.name})

    #     Accounts.update_user(u, %{org_id: org.id})

    #     org.id
    #   end)

    # from(
    #   o in Org,
    #   where: o.id not in ^new_org_ids,
    #   preload: :users
    # )
    # |> Repo.all()
    # |> Enum.filter(fn o -> Enum.empty?(o.users) end)
    # |> Enum.map(fn o -> Repo.delete(o) end)
  end

  def down do
    # There is no going back
  end
end

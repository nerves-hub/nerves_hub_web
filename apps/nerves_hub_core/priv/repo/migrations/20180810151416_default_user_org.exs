defmodule NervesHubCore.Repo.Migrations.DefaultUserOrg do
  import Ecto.Query
  use Ecto.Migration

  alias NervesHubCore.Accounts
  alias NervesHubCore.Accounts.{User, Org}
  alias NervesHubCore.Repo

  def up do
    new_org_ids =
      from(u in User)
      |> Repo.all()
      |> Enum.map(fn u ->
        {:ok, org} = Accounts.create_org(%{name: u.name})

        Accounts.update_user(u, %{org_id: org.id})

        org.id
      end)

    from(
      o in Org,
      where: o.id not in ^new_org_ids,
      preload: :users
    )
    |> Repo.all()
    |> Enum.filter(fn o -> Enum.empty?(o.users) end)
    |> Enum.map(fn o -> Repo.delete(o) end)
  end

  def down do
    # There is no going back
  end
end

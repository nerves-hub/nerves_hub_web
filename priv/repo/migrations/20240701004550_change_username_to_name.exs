defmodule NervesHub.Repo.Migrations.ChangeUsernameToName do
  use Ecto.Migration

  def up do
    drop index("users", [:username], name: "users_username_index")

    rename table("users"), :username, to: :name
  end
end

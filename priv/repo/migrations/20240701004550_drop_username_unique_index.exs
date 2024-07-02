defmodule NervesHub.Repo.Migrations.DropUsernameUniqueIndex do
  use Ecto.Migration

  def up do
    drop index("users", [:username], name: "users_username_index")
  end
end

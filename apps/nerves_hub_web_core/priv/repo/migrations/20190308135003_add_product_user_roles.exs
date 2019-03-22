defmodule NervesHubWebCore.Repo.Migrations.AddProductUserRoles do
  use Ecto.Migration

  alias NervesHubWebCore.Accounts.User.Role

  def change do
    create table(:product_users) do
      add(:product_id, references(:products, on_delete: :delete_all))
      add(:user_id, references(:users, on_delete: :delete_all))
      add(:role, Role.type())
      timestamps()
    end

    create(unique_index(:product_users, [:product_id, :user_id], name: "product_users_index"))
  end
end

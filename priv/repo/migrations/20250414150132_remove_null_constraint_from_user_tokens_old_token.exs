defmodule NervesHub.Repo.Migrations.RemoveNullConstraintFromUserTokensOldToken do
  use Ecto.Migration

  def change do
    alter table(:user_tokens) do
      modify(:old_token, :string, null: true)
    end
  end
end

defmodule NervesHub.Repo.Migrations.AddSentToToUserTokens do
  use Ecto.Migration

  def change() do
    alter table(:user_tokens) do
      add(:sent_to, :string)
    end
  end
end

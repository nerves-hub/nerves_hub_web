defmodule NervesHub.Repo.Migrations.AddBannerToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :banner_upload_key, :string
    end
  end
end

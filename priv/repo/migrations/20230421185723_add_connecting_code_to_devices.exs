defmodule NervesHub.Repo.Migrations.AddConnectingCodeToDevices do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add(:connecting_code, :text)
    end
  end
end

defmodule NervesHub.Repo.Migrations.AddConnectionStatusIndexToDevices do
  use Ecto.Migration
  @disable_ddl_transaction true

  def change do
    create index("devices", [:connection_status], concurrently: true)
  end
end

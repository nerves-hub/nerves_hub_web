defmodule NervesHub.Repo.Migrations.CreateDeviceLogLines do
  use Ecto.Migration

  def change do
    create table(:device_log_lines, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:device_id, references(:devices), null: false)
      add(:product_id, references(:products), null: false)
      add(:level, :string, null: false)
      add(:message, :text, null: false)
      add(:meta, :map, null: false, default: %{})
      add(:logged_at, :naive_datetime_usec, null: false)
    end
  end
end

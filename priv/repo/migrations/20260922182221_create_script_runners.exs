defmodule NervesHub.Repo.Migrations.CreateScriptRunners do
  use Ecto.Migration

  def change() do
    # One row per bulk script execution. These rows are history: `text` records
    # what actually ran, copied from wherever the operator got it, so a run still
    # reads correctly after the script it came from is edited or deleted. Nothing
    # in the application updates `text` once it is written.
    create table(:script_runners) do
      add(:product_id, references(:products, on_delete: :delete_all), null: false)
      add(:created_by_id, references(:users, on_delete: :nothing))

      add(:text, :text, null: false)
      add(:language, :string, null: false, default: "elixir")

      # How the target devices were chosen, and the values that choice needs.
      # A map rather than its own table: the shape differs per filter type, it is
      # only ever read back whole alongside the run, and it is never queried by
      # its contents.
      add(:filter_type, :string, null: false)
      add(:filter, :map, null: false, default: %{})

      add(:status, :string, null: false, default: "pending")

      add(:device_count, :integer, null: false, default: 0)
      add(:started_at, :utc_datetime_usec)
      add(:finished_at, :utc_datetime_usec)

      timestamps()
    end

    # Listing a product's runs, newest first.
    create(index(:script_runners, [:product_id]))

    # Every dispatch divides the concurrency budget by the number of runs in
    # flight, so this count is read far more often than the rows change. Partial,
    # because finished runs are the overwhelming majority and never match.
    create(index(:script_runners, [:status], where: "status IN ('pending', 'running')"))
  end
end

defmodule NervesHub.Repo.Migrations.CreateTeamsChannels do
  use Ecto.Migration

  def change() do
    # A Microsoft Teams channel an organization's device events are posted
    # to, through a Workflows webhook somebody made in that channel. The URL
    # is encrypted: its signature is all it takes to post there.
    create table(:teams_channels) do
      add(:org_id, references(:orgs, on_delete: :delete_all), null: false)
      add(:name, :string, null: false)
      add(:url, :binary, null: false)
      add(:url_host, :string, null: false)
      add(:events, {:array, :string}, null: false, default: [])
      add(:all_products, :boolean, null: false, default: true)
      add(:enabled, :boolean, null: false, default: true)
      add(:disabled_reason, :string)
      add(:last_error, :text)
      add(:last_error_at, :utc_datetime)

      timestamps()
    end

    create(index(:teams_channels, [:org_id]))

    # The products a channel is limited to, when it is not posting every
    # product's events (`all_products`).
    create table(:teams_channel_products, primary_key: false) do
      add(:channel_id, references(:teams_channels, on_delete: :delete_all), null: false)
      add(:product_id, references(:products, on_delete: :delete_all), null: false)
    end

    create(unique_index(:teams_channel_products, [:channel_id, :product_id]))
    create(index(:teams_channel_products, [:product_id]))

    # Events waiting to be posted, gathered so that a burst goes out as one
    # card rather than one per device.
    create table(:teams_pending_events) do
      add(:channel_id, references(:teams_channels, on_delete: :delete_all), null: false)
      add(:type, :string, null: false)
      add(:data, :map, null: false)

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create(index(:teams_pending_events, [:channel_id, :id]))
  end
end

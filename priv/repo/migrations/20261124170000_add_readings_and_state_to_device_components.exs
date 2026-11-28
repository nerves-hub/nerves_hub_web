defmodule NervesHub.Repo.Migrations.AddReadingsAndStateToDeviceComponents do
  use Ecto.Migration

  def change() do
    # Readings and state, from the `components` extension: what each component
    # last measured and what state it is in, kept with the component for the device
    # page's list and side panel. Their history is in ClickHouse
    # (`device_component_readings`, and `state_changed` rows in
    # `device_component_history`). See docs/components.md.
    alter table(:device_components) do
      # `{name => %{"value" => number, "at" => ISO 8601}}`, merged from each
      # `components:readings` report, so a component that reports its battery
      # less often than its temperature keeps both.
      add(:readings, :map, null: false, default: %{})

      # The newest `at` in `readings`.
      add(:readings_at, :utc_datetime_usec)

      # `{name => %{"value" => string, "since" => ISO 8601, "detail" => string | nil}}`,
      # set by `components:state` and replaced by a snapshot that carries state.
      add(:state, :map, null: false, default: %{})
    end
  end
end

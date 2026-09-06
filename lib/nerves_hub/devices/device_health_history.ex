defmodule NervesHub.Devices.DeviceHealthHistory do
  @moduledoc """
  One health verdict transition on one device.

  Rows are batched into ClickHouse by `NervesHub.Analytics.Buffer`. Where
  `NervesHub.Devices.DeviceHealth` answers "what is this device's status now",
  this answers "what was it, and when did it change" — how long a level held
  is the gap to the next row, a window function rather than a row this has to
  keep mutable.

  Only transitions are written, never the steady state. A device reports every
  few minutes and its status changes far more rarely than that, so the volume
  is a fraction of `device_metrics` even though rows are kept three times as
  long.

  ## Why this exists rather than recomputing

  A status is derived from the profile's thresholds and the stored readings,
  so it looks like something that can simply be recomputed. It cannot, for
  two reasons.

  Thresholds are per product and editable (`NervesHub.Products.HealthProfiles`).
  Recomputing a past status applies today's thresholds to yesterday's
  readings, which answers "would we call that unhealthy now" rather than "did
  we call it unhealthy then" — the wrong question for a deployment gate or an
  audit. `status_reasons` is carried on the row for the same reason: it names
  the threshold and the period that were in force, so a row stays true after
  somebody edits the profile.

  And the readings themselves expire before these rows do. Past the
  `device_metrics` TTL there is nothing left to recompute from, so this table
  is the only thing that can still say what a device's status was.

  ## What it does not record

  Transitions are observed from reports, so a device that stops reporting
  keeps its last verdict and writes nothing further. A range query that means
  "how much of the fleet was healthy" should narrow on connection status
  rather than assume every device was reporting throughout.

  Rows also ride `NervesHub.Analytics.Buffer`, which sheds its oldest rows if
  ClickHouse stays unreachable. Like every other analytics write, this is a
  faithful record of what the platform saw rather than a ledger that cannot
  lose an entry.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key false
  schema "device_health_history" do
    field(:timestamp, Ch, type: "DateTime64(6, 'UTC')")

    field(:org_id, Ch, type: "UInt64")
    field(:product_id, Ch, type: "UInt64")
    field(:device_id, Ch, type: "UInt64")

    field(:status, Ch, type: "LowCardinality(String)")

    # The `status_reasons` map as JSON; empty when no level is engaged.
    field(:status_reasons, Ch, type: "String", default: "")
  end

  @doc """
  Builds a row for `NervesHub.Analytics.Buffer` to batch.

  Changes the struct directly rather than casting, as `DeviceAlarmHistory`
  does: the caller is holding a verdict the database has already accepted, so
  there is nothing left to validate. The buffer flattens the changeset back
  through the struct to fill in untouched fields, since `insert_all` builds
  one statement per batch and every row has to carry the same columns.
  """
  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs), do: change(%__MODULE__{}, attrs)
end

defmodule NervesHub.Devices.DeviceUpdateHistory do
  @moduledoc """
  One finished firmware update attempt on one device.

  Rows are batched into ClickHouse by `NervesHub.Analytics.Buffer`. Where
  `NervesHub.Devices.InflightUpdate` answers "what is this device doing right
  now", this answers "what came of it" — an append-only record of attempts that
  reached an outcome, which the inflight row cannot be, because reaching an
  outcome is what deletes it.

  Only outcomes are written, never progress. A device reports `downloading` and
  `updating` repeatedly through a single update; one row is written when that
  update ends, whichever way it ends.

  See `NervesHub.Devices.UpdateHistory` for what each status means, which of
  them count as a failure, and the queries that read this table.

  ## What it does not record

  Rows ride `NervesHub.Analytics.Buffer`, which sheds its oldest rows if
  ClickHouse stays unreachable, and the table is only written where
  `:analytics_enabled` is set. Like every other analytics write, this is a
  faithful record of what the platform saw rather than a ledger that cannot
  lose an entry — which is why the device's consecutive failure count is a
  column on `devices` in PostgreSQL rather than something counted from here.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key false
  schema "device_update_history" do
    field(:timestamp, Ch, type: "DateTime64(6, 'UTC')")

    field(:org_id, Ch, type: "UInt64")
    field(:product_id, Ch, type: "UInt64")
    field(:device_id, Ch, type: "UInt64")

    # 0 when no deployment group asked for the update — see the migration.
    field(:deployment_id, Ch, type: "UInt64", default: 0)

    field(:status, Ch, type: "LowCardinality(String)")

    field(:source_firmware_uuid, Ch, type: "String", default: "")
    field(:target_firmware_uuid, Ch, type: "String", default: "")

    field(:reason, Ch, type: "String", default: "")
  end

  @doc """
  Builds a row for `NervesHub.Analytics.Buffer` to batch.

  Changes the struct directly rather than casting, as `DeviceHealthHistory` and
  `DeviceAlarmHistory` do: `NervesHub.Devices.UpdateHistory` has already
  normalised the status and the firmware uuids by this point. The buffer
  flattens the changeset back through the struct to fill in untouched fields,
  since `insert_all` builds one statement per batch and every row has to carry
  the same columns.
  """
  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs), do: change(%__MODULE__{}, attrs)
end

defmodule NervesHub.ErrorReports.ErrorReport do
  @moduledoc """
  One occurrence of an error on one device.

  Rows are batched into ClickHouse by `NervesHub.Analytics.Buffer` and read on
  drill-down — the stacktrace behind an issue, the devices it has hit, its shape
  over time. Never on a list page: what the product page lists is
  `NervesHub.ErrorReports.ErrorGroup`, which is in PostgreSQL precisely so that
  page does not touch this table.

  Occurrences are dropped after thirty days. The group row survives, keeping the
  counts and the first-seen.

  ## Device vitals live in `context`

  Uptime, reboot count, free memory and anything else a device can say about its
  own state go in the context map rather than in columns of their own. Those
  three are what a BEAM device happens to report; a device reporting free heap
  and signal strength instead would otherwise need a migration to say so.

  `firmware_uuid` is the exception, because it is the one piece of device state
  the platform itself fills in and the group row carries.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key false
  schema "device_error_reports" do
    field(:timestamp, Ch, type: "DateTime64(6, 'UTC')")

    field(:org_id, Ch, type: "UInt64")
    field(:product_id, Ch, type: "UInt64")
    field(:device_id, Ch, type: "UInt64")

    field(:fingerprint, Ch, type: "String")

    field(:kind, Ch, type: "LowCardinality(String)")
    field(:source, Ch, type: "LowCardinality(String)", default: "logger")

    field(:reason, Ch, type: "String", default: "")
    field(:message, Ch, type: "String", default: "")

    # A JSON array of frames, innermost first. See
    # `NervesHub.ErrorReports.Payload` for the shape and the cap.
    field(:frames, Ch, type: "String", default: "[]")

    field(:context, Ch, type: "Map(LowCardinality(String), String)", default: %{})

    field(:firmware_uuid, Ch, type: "LowCardinality(String)", default: "")

    field(:payload_bytes, Ch, type: "UInt32", default: 0)
    field(:truncated, Ch, type: "UInt8", default: 0)
  end

  @doc """
  Builds a row for `NervesHub.Analytics.Buffer` to batch.

  Changes the struct directly rather than casting, the same as
  `NervesHub.Devices.DeviceMessage`: by this point every value has already been
  validated and capped by `NervesHub.ErrorReports.Payload`, so a second pass
  through `cast/3` would only re-check what is known good. The buffer flattens
  the changeset through the struct, which fills in the defaults above — that
  matters because `insert_all` builds one statement per batch and every row has
  to carry the same columns.
  """
  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs), do: change(%__MODULE__{}, attrs)

  @doc """
  True when the stored report is only part of what the device sent.
  """
  @spec truncated?(t()) :: boolean()
  def truncated?(%__MODULE__{truncated: truncated}), do: truncated == 1

  @doc """
  The frames, decoded back into a list of maps.

  Returns `[]` for anything unreadable rather than raising. A row whose frames
  cannot be decoded is still worth rendering — the reason and the context are
  the parts most often needed, and losing the whole page over a bad blob would
  be the wrong trade.
  """
  @spec frames(t()) :: [map()]
  def frames(%__MODULE__{frames: frames}) when is_binary(frames) do
    case Jason.decode(frames) do
      {:ok, decoded} when is_list(decoded) -> decoded
      _ -> []
    end
  end

  def frames(%__MODULE__{}), do: []
end

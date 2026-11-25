defmodule NervesHub.Devices.ReportedMetadata do
  @moduledoc """
  The metadata a device reports about itself, and the limits on it.

  Both ways a device reports metadata end in `merge/2`: the device channel's
  `report_device_metadata` message, and the `metadata` key of a health report
  from firmware older than that message. It is merged into the connection's
  `metadata` column (`NervesHub.Devices.Connections.merge_update_metadata/2`),
  beside keys the platform writes there itself. See `docs/device_metadata.md`.

  A device can send this whenever it likes, so what it sends is trimmed
  rather than trusted:

    * Keys the platform writes to the same column (`connection_types`,
      `device_api_version`, `location`) are dropped, so a device can't overwrite them.
    * A key longer than 64 bytes, or a value longer than 256 bytes as JSON,
      is dropped.
    * At most 32 keys are kept, the first in sorted order, so a device over
      the limit loses the same keys every time.
    * Metadata that isn't a map is dropped whole.

  Whatever is left is still stored, and what was dropped is logged.
  """

  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Connections

  require Logger

  # docs/device_metadata.md and the moduledoc above give these too.
  @reserved_keys ~w(connection_types device_api_version location)
  @max_keys 32
  @max_key_bytes 64
  @max_value_bytes 256

  @typedoc """
  Why keys were dropped, in the order they are checked.
  """
  @type reason :: :reserved | :too_long | :too_many

  @typedoc """
  What `trim/1` dropped: why, how many keys, and one of them to show.
  """
  @type dropped :: %{reasons: [reason()], count: non_neg_integer(), example_key: String.t() | nil}

  @doc "How many keys are kept."
  def max_keys(), do: @max_keys

  @doc "The longest key kept, in bytes."
  def max_key_bytes(), do: @max_key_bytes

  @doc "The longest value kept, in bytes of JSON."
  def max_value_bytes(), do: @max_value_bytes

  @doc """
  Merges `metadata` into the device's connection, within the limits above.

  `nil`, an empty map, and a map with nothing left after trimming leave the
  connection alone. An error writing only means the connection row has
  already moved on, which the next report will correct, so it is logged and
  `:ok` is returned either way.
  """
  @spec merge(DeviceInfo.t(), term()) :: :ok
  def merge(_device_info, nil), do: :ok
  def merge(_device_info, metadata) when metadata == %{}, do: :ok

  def merge(%DeviceInfo{} = device_info, metadata) when is_map(metadata) do
    {kept, dropped} = trim(metadata)

    if dropped.count > 0 do
      Logger.info(
        "[ReportedMetadata] dropped #{dropped.count} metadata keys from #{device_info.device_identifier}: #{inspect(dropped.reasons)}"
      )
    end

    write(device_info, kept)
  end

  def merge(%DeviceInfo{} = device_info, _not_a_map) do
    Logger.info("[ReportedMetadata] dropped metadata that isn't a map from #{device_info.device_identifier}")
    :ok
  end

  @doc """
  Splits `metadata` into what is kept and what was dropped, and why.
  """
  @spec trim(map()) :: {map(), dropped()}
  def trim(metadata) when is_map(metadata) do
    {reserved, rest} = Enum.split_with(metadata, fn {key, _value} -> key in @reserved_keys end)
    {too_long, rest} = Enum.split_with(rest, fn {key, value} -> not fits?(key, value) end)
    {kept, too_many} = rest |> Enum.sort_by(fn {key, _value} -> key end) |> Enum.split(@max_keys)

    dropped = [reserved: reserved, too_long: too_long, too_many: too_many]
    reasons = for {reason, [_ | _]} <- dropped, do: reason
    dropped_keys = Enum.flat_map(dropped, fn {_reason, pairs} -> Enum.map(pairs, &elem(&1, 0)) end)

    {Map.new(kept),
     %{
       reasons: reasons,
       count: length(dropped_keys),
       example_key: example_key(dropped_keys)
     }}
  end

  # JSON keys are always strings; anything else is a caller bug, and dropped.
  defp fits?(key, value) when is_binary(key) do
    byte_size(key) <= @max_key_bytes and
      case Jason.encode(value) do
        {:ok, json} -> byte_size(json) <= @max_value_bytes
        {:error, _reason} -> false
      end
  end

  defp fits?(_key, _value), do: false

  defp example_key([]), do: nil
  defp example_key([key | _rest]) when is_binary(key), do: String.slice(key, 0, @max_key_bytes)
  defp example_key([key | _rest]), do: inspect(key)

  defp write(_device_info, kept) when kept == %{}, do: :ok

  defp write(device_info, kept) do
    case Connections.merge_update_metadata(device_info.connection_ref, kept) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("[ReportedMetadata] failed to merge reported metadata: #{inspect(reason)}")
        :ok
    end
  end
end

defmodule NervesHub.Devices.LogLines do
  @moduledoc """
  Device logging storage and querying.
  """

  import Ecto.Query

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.LogLine
  alias Phoenix.Channel.Server, as: ChannelServer

  @type log_line_payload :: %{
          timestamp: DateTime.t(),
          level: String.t(),
          message: String.t(),
          meta: map()
        }

  @default_limit 25

  @typedoc """
  How to narrow a device's logs.

  - `:levels` — only these levels. A device is free to log at any level it
    likes, so this is matched as given rather than against a fixed list.
  - `:since` — at or after this time (inclusive).
  - `:before` — strictly before this time (exclusive), so the timestamp of the
    oldest line in a page can be passed straight back as the next page's
    `:before` without repeating that line.
  - `:limit` — how many lines to return, newest first unless `:order` says
    otherwise. Defaults to #{@default_limit}.
  - `:order` — `:desc` (newest first, the default) or `:asc`.
  """
  @type filter_opt ::
          {:levels, [String.t()] | nil}
          | {:since, DateTime.t() | nil}
          | {:before, DateTime.t() | nil}
          | {:limit, pos_integer()}
          | {:order, :asc | :desc}

  @doc """
  Retrieves the most recent #{@default_limit} log lines for a device.

  ## Examples

      iex> recent(device)
      [%LogLine{}, %LogLine{}]

  """
  @spec recent(Device.t()) :: list(LogLine.t())
  def recent(device), do: for_device(device)

  @doc """
  Retrieves a device's log lines, newest first, narrowed by `opts`.

  See `t:filter_opt/0` for what can be narrowed.

  ## Examples

      iex> for_device(device, levels: ["error"], limit: 10)
      [%LogLine{}, %LogLine{}]

  """
  @spec for_device(Device.t(), [filter_opt()]) :: list(LogLine.t())
  def for_device(%Device{} = device, opts \\ []) do
    order = Keyword.get(opts, :order, :desc)
    limit = Keyword.get(opts, :limit, @default_limit)

    LogLine
    |> where(product_id: ^device.product_id)
    |> where(device_id: ^device.id)
    |> filter_levels(Keyword.get(opts, :levels))
    |> filter_since(Keyword.get(opts, :since))
    |> filter_before(Keyword.get(opts, :before))
    |> order_by([l], [{^order, l.timestamp}])
    |> limit(^limit)
    |> AnalyticsRepo.all()
  end

  defp filter_levels(query, nil), do: query
  defp filter_levels(query, []), do: query
  defp filter_levels(query, levels), do: where(query, [l], l.level in ^levels)

  defp filter_since(query, nil), do: query
  defp filter_since(query, %DateTime{} = since), do: where(query, [l], l.timestamp >= ^since)

  defp filter_before(query, nil), do: query
  defp filter_before(query, %DateTime{} = before), do: where(query, [l], l.timestamp < ^before)

  @doc """
  Creates a log line for a device.

  ## Examples

      iex> create!(device, %{level: :info, message: "Hello", meta: %{}, timestamp: DateTime.utc_now()})
      %LogLine{}

  """
  @spec async_create(DeviceInfo.t(), log_line_payload) ::
          {:ok, LogLine.t()} | {:error, Ecto.Changeset.t()}
  def async_create(%DeviceInfo{} = device_info, attrs) do
    changeset = LogLine.create_changeset(device_info.device_id, device_info.product_id, attrs)

    case Ecto.Changeset.apply_action(changeset, :create) do
      {:ok, log_line} ->
        _ = Buffer.insert(LogLine, changeset)

        _ =
          ChannelServer.broadcast(
            NervesHub.PubSub,
            "internal:device:#{device_info.device_id}",
            "logs:received",
            log_line
          )

        {:ok, log_line}

      error ->
        error
    end
  end
end

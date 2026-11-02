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
  alias NervesHub.Devices.PubSub

  @typedoc """
  One log line, as a device sends it.

  String keys, because that is how it arrives over the channel and how
  `NervesHub.Devices.LogLine.create_changeset/3` casts it — a payload with atom
  keys is not a stricter version of this, it is one `Ecto.Changeset.cast/3`
  refuses.

  `"level"` and `"message"` are required. The timestamp is either `"timestamp"`
  or `"meta" => %{"time" => microseconds}`, which is where every client puts
  it; a line with neither is dropped, since a line the server timestamps on
  arrival would claim the device wrote it whenever the network got around to
  delivering it.
  """
  @type log_line_payload :: %{optional(String.t()) => term()}

  @default_limit 25

  @typedoc """
  How to narrow a device's logs.

  - `:levels` — only these levels. A device is free to log at any level it
    likes, so this is matched as given rather than against a fixed list.
  - `:search` — only lines whose message contains this text, ignoring case.
    Matched literally: a device that logs `100%` is found by searching for
    `100%`, not by a wildcard.
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
          | {:search, String.t() | nil}
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
    |> filter_search(Keyword.get(opts, :search))
    |> filter_since(Keyword.get(opts, :since))
    |> filter_before(Keyword.get(opts, :before))
    |> order_by([l], [{^order, l.timestamp}])
    |> limit(^limit)
    |> AnalyticsRepo.all()
  end

  defp filter_levels(query, nil), do: query
  defp filter_levels(query, []), do: query
  defp filter_levels(query, levels), do: where(query, [l], l.level in ^levels)

  defp filter_search(query, nil), do: query
  defp filter_search(query, ""), do: query

  # positionCaseInsensitive rather than ILIKE, so the needle is taken literally
  # — a message full of `%` or `_` is searchable without anyone escaping it.
  defp filter_search(query, search) do
    where(query, [l], fragment("positionCaseInsensitive(?, ?) > 0", l.message, ^search))
  end

  defp filter_since(query, nil), do: query
  defp filter_since(query, %DateTime{} = since), do: where(query, [l], l.timestamp >= ^since)

  defp filter_before(query, nil), do: query
  defp filter_before(query, %DateTime{} = before), do: where(query, [l], l.timestamp < ^before)

  @doc """
  Whether `log_line` is one `for_device/2` would return for the same filters.

  For a line that has just arrived, where there is no query to ask: the Logs tab
  streams new lines to someone who has narrowed what they are looking at, and a
  line they did not ask for should not appear. Takes the filters `for_device/2`
  does; `:limit` and `:order` say how many lines to return, not which, and are
  ignored.

  Case is folded for ASCII only, because that is all `positionCaseInsensitive`
  does in the query. Folding more here would show a line live that is gone the
  next time the page is loaded.

  ## Examples

      iex> matches?(%LogLine{level: "error", message: "Sensor bus gone"}, levels: ["error"], search: "sensor")
      true

  """
  @spec matches?(LogLine.t(), [filter_opt()]) :: boolean()
  def matches?(%LogLine{} = log_line, opts \\ []) do
    level_matches?(log_line, Keyword.get(opts, :levels)) and
      search_matches?(log_line, Keyword.get(opts, :search)) and
      since_matches?(log_line, Keyword.get(opts, :since)) and
      before_matches?(log_line, Keyword.get(opts, :before))
  end

  defp level_matches?(_log_line, levels) when levels in [nil, []], do: true
  defp level_matches?(log_line, levels), do: log_line.level in levels

  defp search_matches?(_log_line, search) when search in [nil, ""], do: true

  defp search_matches?(log_line, search) do
    String.contains?(ascii_downcase(log_line.message), ascii_downcase(search))
  end

  defp since_matches?(_log_line, nil), do: true
  defp since_matches?(log_line, %DateTime{} = since), do: DateTime.compare(log_line.timestamp, since) != :lt

  defp before_matches?(_log_line, nil), do: true
  defp before_matches?(log_line, %DateTime{} = before), do: DateTime.before?(log_line.timestamp, before)

  # `String.downcase/1` folds every script, which ClickHouse's
  # `positionCaseInsensitive` does not.
  defp ascii_downcase(string) do
    for <<char <- string>>, into: "", do: <<if(char in ?A..?Z, do: char + 32, else: char)>>
  end

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
          PubSub.broadcast(
            device_info.device_id,
            "logs:received",
            log_line
          )

        {:ok, log_line}

      error ->
        error
    end
  end

  @doc """
  Creates several log lines for a device, in the order they were sent.

  One row per line, the same as `async_create/2` a line at a time: the batch is
  how the device got them here, not how they are stored. `NervesHub.Analytics.Buffer`
  is what turns rows into ClickHouse inserts, and it batches across devices, so
  there is nothing to gain by keeping a device's lines together past this point.

  Lines that do not validate are skipped rather than failing their neighbours.
  A device that gets one line wrong should not lose the rest of the second.

  Returns how many were stored.

  ## Examples

      iex> async_create_many(device_info, [%{"level" => "info", "message" => "Hello"}])
      {:ok, 1}

  """
  @spec async_create_many(DeviceInfo.t(), [log_line_payload]) :: {:ok, non_neg_integer()}
  def async_create_many(%DeviceInfo{} = device_info, lines) when is_list(lines) do
    stored =
      Enum.count(lines, fn line ->
        match?({:ok, _log_line}, async_create(device_info, line))
      end)

    {:ok, stored}
  end
end

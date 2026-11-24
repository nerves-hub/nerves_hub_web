defmodule NervesHub.Devices.ConnectionTimeline do
  @moduledoc """
  When a device was connected over a span of time, read from the connection
  history in ClickHouse, for the connection lane on the device's Health tab
  and the Offline bands on its charts.

  A timeline holds two things:

    * `offline`, the times the device had no connection for a minute or more,
      oldest first. Each has the reason the connection before it ended ("" if
      it closed without one, nil if no connection is known before it), and
      the network interface and address the device came back on. One that
      began before the span starts when its connection really ended, and one
      the device hasn't come back from has no `until`.
    * `reconnects`, when the device opened a new connection less than a
      minute after the last one, or while the last was still open. Too short
      to show as time offline, but worth marking.

  Callers are expected to check that analytics is enabled first.
  """

  import Ecto.Query

  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices.DeviceConnectionHistory

  # Gaps shorter than this are a reconnect rather than time offline. Matches
  # how long the device socket waits before calling a connection gone.
  @shortest_offline_seconds 60

  @type offline :: %{
          from: DateTime.t(),
          until: DateTime.t() | nil,
          reason: String.t() | nil,
          interface: String.t() | nil,
          ip_address: String.t() | nil
        }

  @type t :: %__MODULE__{offline: [offline()], reconnects: [DateTime.t()]}

  defstruct offline: [], reconnects: []

  @typep connection :: %{
           established_at: DateTime.t(),
           disconnected_at: DateTime.t() | nil,
           reason: String.t() | nil,
           interface: String.t() | nil,
           ip_address: String.t() | nil
         }

  @doc """
  The device's timeline between `from` and `until`.

  Reads the connections that overlap the span, and the last one to end before
  it, so time offline at the start of the span says when and why it began.
  """
  @spec load(%{id: pos_integer(), org_id: pos_integer(), product_id: pos_integer()}, DateTime.t(), DateTime.t()) ::
          t()
  def load(device, from, until) do
    connections =
      device
      |> history()
      |> where([dc], dc.established_at <= ^until)
      |> where([dc], is_nil(dc.disconnected_at) or dc.disconnected_at >= ^from)
      |> AnalyticsRepo.all(settings: [final: 1])

    previous =
      device
      |> history()
      |> where([dc], dc.disconnected_at < ^from)
      |> order_by([dc], desc: dc.disconnected_at)
      |> limit(1)
      |> AnalyticsRepo.one(settings: [final: 1])

    build(connections, previous, from, until)
  end

  defp history(%{id: device_id, org_id: org_id, product_id: product_id}) do
    DeviceConnectionHistory
    |> where([dc], dc.org_id == ^org_id and dc.product_id == ^product_id and dc.device_id == ^device_id)
    |> select([dc], %{
      established_at: dc.established_at,
      disconnected_at: dc.disconnected_at,
      reason: dc.disconnected_reason,
      interface: dc.network_interface,
      ip_address: dc.ip_address
    })
  end

  @doc """
  Builds a timeline between `from` and `until` out of `connections` and `previous`.

  `connections` come in any order and may overlap; one with no
  `disconnected_at` is still open. `previous` is the last connection to end
  before `from`, or nil. An empty interface or address, which the history
  stores for a value it didn't have, comes out as nil. An empty reason stays
  empty, since it means the connection closed without one.
  """
  @spec build([connection()], connection() | nil, DateTime.t(), DateTime.t()) :: t()
  def build(connections, previous, from, until) do
    # Where the device's coverage reaches so far, and the connection that got
    # it there. Before any connection that's `from`, or where `previous` ended.
    start =
      case previous do
        %{disconnected_at: %DateTime{} = ended} -> {ended, clean(previous)}
        _none -> {from, nil}
      end

    {{covered_to, last}, offline, reconnects} =
      connections
      |> Enum.map(&clean/1)
      |> Enum.sort_by(& &1.established_at, DateTime)
      |> Enum.reduce({start, [], []}, &step(&1, &2, from, until))

    offline =
      if offline_since?(covered_to, until) do
        [offline(covered_to, nil, last, nil) | offline]
      else
        offline
      end

    %__MODULE__{offline: Enum.reverse(offline), reconnects: Enum.reverse(reconnects)}
  end

  # Counts one connection, oldest first: the time offline before it if there
  # was a minute or more without a connection, or a reconnect if there wasn't.
  # One that opened before `from` or after `until` only extends the coverage.
  defp step(%{established_at: established_at} = connection, {{covered_to, last}, offline, reconnects}, from, until) do
    {offline, reconnects} =
      cond do
        not DateTime.after?(established_at, from) ->
          {offline, reconnects}

        offline_since?(covered_to, established_at) ->
          {[offline(covered_to, established_at, last, connection) | offline], reconnects}

        DateTime.after?(established_at, until) ->
          {offline, reconnects}

        true ->
          {offline, [established_at | reconnects]}
      end

    {cover(covered_to, last, connection), offline, reconnects}
  end

  defp offline_since?(:open, _at), do: false
  defp offline_since?(covered_to, at), do: DateTime.diff(at, covered_to) >= @shortest_offline_seconds

  # How far coverage reaches once `connection` is counted: to its end, or
  # without end while it's open.
  defp cover(:open, last, _connection), do: {:open, last}
  defp cover(_covered_to, _last, %{disconnected_at: nil} = connection), do: {:open, connection}

  defp cover(covered_to, last, %{disconnected_at: ended} = connection) do
    if DateTime.after?(ended, covered_to), do: {ended, connection}, else: {covered_to, last}
  end

  defp offline(from, until, ended, came_back) do
    %{
      from: from,
      until: until,
      reason: ended && ended.reason,
      interface: came_back && came_back.interface,
      ip_address: came_back && came_back.ip_address
    }
  end

  defp clean(connection) do
    Map.new(connection, fn
      {key, ""} when key in [:interface, :ip_address] -> {key, nil}
      pair -> pair
    end)
  end

  @doc """
  The offline times between `from` and `until`, cut to it, as `[[from, until]]`
  in unix milliseconds, for the charts to shade.

  One the device hasn't come back from runs to `until`.
  """
  @spec offline_periods(t(), DateTime.t(), DateTime.t()) :: [[integer()]]
  def offline_periods(%__MODULE__{offline: offline}, from, until) do
    for span <- offline, {start, stop} <- [clip(span, from, until)], DateTime.before?(start, stop) do
      [DateTime.to_unix(start, :millisecond), DateTime.to_unix(stop, :millisecond)]
    end
  end

  @doc """
  What the timeline adds up to between `from` and `until`: the share of it the
  device was online, as a whole percent, the times it disconnected (offline
  times that began inside it) and the times it reconnected.

  The share is only 100 when the device was never offline in the span, and
  only 0 when it was never online.
  """
  @spec summary(t(), DateTime.t(), DateTime.t()) :: %{
          online_percent: 0..100,
          disconnects: non_neg_integer(),
          reconnects: non_neg_integer()
        }
  def summary(%__MODULE__{offline: offline, reconnects: reconnects}, from, until) do
    total = max(DateTime.diff(until, from, :millisecond), 1)

    offline_ms =
      Enum.sum_by(offline, fn span ->
        {start, stop} = clip(span, from, until)
        max(DateTime.diff(stop, start, :millisecond), 0)
      end)

    %{
      online_percent: percent(total - offline_ms, total),
      disconnects: Enum.count(offline, &within?(&1.from, from, until)),
      reconnects: Enum.count(reconnects, &within?(&1, from, until))
    }
  end

  defp percent(part, total) when part >= total, do: 100
  defp percent(part, _total) when part <= 0, do: 0
  defp percent(part, total), do: (part * 100 / total) |> round() |> max(1) |> min(99)

  @doc """
  Cuts an offline time to between `from` and `until`, running one the device
  hasn't come back from to `until`.
  """
  @spec clip(offline(), DateTime.t(), DateTime.t()) :: {DateTime.t(), DateTime.t()}
  def clip(%{from: start, until: stop}, from, until) do
    {latest(start, from), earliest(stop || until, until)}
  end

  defp within?(at, from, until), do: not DateTime.before?(at, from) and not DateTime.after?(at, until)

  defp latest(a, b), do: if(DateTime.after?(a, b), do: a, else: b)
  defp earliest(a, b), do: if(DateTime.before?(a, b), do: a, else: b)
end

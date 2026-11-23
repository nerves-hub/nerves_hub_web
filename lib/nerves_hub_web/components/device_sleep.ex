defmodule NervesHubWeb.Components.DeviceSleep do
  @moduledoc """
  How a device that sleeps between reports is shown: asleep and when it is due
  back, or overdue, rather than the same grey dot as a device that has gone.

  The state comes from `NervesHub.Devices.DeviceConnection.sleep_state/2`.
  """

  use Phoenix.Component

  import NervesHubWeb.CoreComponents, only: [badge: 1, tooltip: 1]

  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Helpers.RelativeTime
  alias NervesHubWeb.Components.DateTimes

  @doc """
  A badge for the device page header, with when the device is due back in a
  tooltip. Renders nothing for a connection that did not end in sleep.
  """
  attr(:id, :string, required: true)
  attr(:connection, :any, required: true, doc: "the device's latest `DeviceConnection`, or nil")
  attr(:time_zone, :string, default: nil)

  attr(:now, DateTime,
    default: nil,
    doc: "the time to judge it at; pass a ticking assign so the badge follows the clock"
  )

  def sleep_badge(assigns) do
    now = assigns.now || DateTime.utc_now()
    assigns = assign(assigns, now: now, state: DeviceConnection.sleep_state(assigns.connection, now))

    ~H"""
    <.tooltip :if={@state} id={@id} placement="bottom">
      <.badge tone={if @state == :overdue, do: "warning", else: "neutral"} class="flex items-center gap-1">
        <span class="lucide-moon--bold size-3" aria-hidden="true"></span>
        {summary(@state, @connection, @now)}
      </.badge>
      <:content>
        {detail(@state, @connection, @time_zone)}
      </:content>
    </.tooltip>
    """
  end

  @doc """
  The device list's status for a device: `"online"`, `"offline"`, `"asleep"`
  or `"overdue"`. A device going to sleep is still online until its
  connection closes.
  """
  @spec list_status(DeviceConnection.t() | nil, DateTime.t()) :: String.t()
  def list_status(connection, now \\ DateTime.utc_now())

  def list_status(%DeviceConnection{status: :connected}, _now), do: "online"

  def list_status(connection, now) do
    case DeviceConnection.sleep_state(connection, now) do
      :asleep -> "asleep"
      :overdue -> "overdue"
      _ -> "offline"
    end
  end

  @doc """
  The status dot's colour for a status from `list_status/1`.
  """
  @spec dot_class(String.t() | nil) :: String.t()
  def dot_class("online"), do: "bg-status-online"
  def dot_class("asleep"), do: "bg-status-asleep"
  def dot_class("overdue"), do: "bg-warning"
  def dot_class(_status), do: "bg-status-offline"

  @doc """
  The `title` for the dot `dot_class/1` colours: "Online", "Offline", or for
  a sleeping device what `describe/1` says about it.
  """
  @spec dot_title(String.t() | nil, DeviceConnection.t() | nil) :: String.t()
  def dot_title("online", _connection), do: "Online"
  def dot_title(status, connection) when status in ["asleep", "overdue"], do: describe(connection) || "Offline"
  def dot_title(_status, _connection), do: "Offline"

  @doc """
  A sentence for a `title` or tooltip about a sleeping device, such as
  "Asleep, back in 5 minutes", or nil when it is not asleep.
  """
  @spec describe(DeviceConnection.t() | nil) :: String.t() | nil
  def describe(connection) do
    now = DateTime.utc_now()

    case DeviceConnection.sleep_state(connection, now) do
      nil -> nil
      state -> summary(state, connection, now)
    end
  end

  defp summary(:going_to_sleep, _connection, _now), do: "Going to sleep"
  defp summary(:asleep, %{expected_wake_at: nil}, _now), do: "Asleep"

  defp summary(:asleep, %{expected_wake_at: at}, now) do
    if DateTime.after?(at, now), do: "Asleep, back #{RelativeTime.from_now(at, now)}", else: "Asleep, due back now"
  end

  defp summary(:overdue, %{expected_wake_at: at}, now), do: "Overdue, was due #{RelativeTime.from_now(at, now)}"

  defp detail(state, connection, time_zone) do
    mode = if connection.disconnected_reason == :light_sleep, do: "light", else: "deep"

    case {state, connection.expected_wake_at} do
      {_state, nil} ->
        "In #{mode} sleep until something wakes it. It gave no time."

      {:overdue, at} ->
        "Went into #{mode} sleep and said it would be back at #{DateTimes.to_local_string(at, time_zone, :short_datetime)}. It has not connected since."

      {_state, at} ->
        "In #{mode} sleep. Expected back at #{DateTimes.to_local_string(at, time_zone, :short_datetime)}."
    end
  end
end

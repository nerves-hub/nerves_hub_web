defmodule NervesHubWeb.Components.DeviceSleep do
  @moduledoc """
  How a device that sleeps between reports is shown: two rising z's in place
  of its status dot, green while it is asleep and orange once it is later
  than it said it would be, rather than the grey dot of a device that has
  gone.

  The state comes from `NervesHub.Devices.DeviceConnection.sleep_state/2`.
  """

  use Phoenix.Component

  import NervesHubWeb.CoreComponents, only: [status_dot: 1, tooltip: 1]

  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Helpers.RelativeTime
  alias NervesHubWeb.Components.DateTimes

  @doc """
  The two z's that stand in for a sleeping device's status dot. The
  `sleep-mark` utility sizes them; add `sleep-mark-lg` for the device page
  header.
  """
  attr(:status, :string, required: true, values: ["asleep", "overdue"])
  attr(:title, :string, required: true, doc: "what the mark says, for its tooltip and screen readers")
  attr(:class, :any, default: nil)
  attr(:rest, :global)

  def sleep_mark(assigns) do
    ~H"""
    <span role="img" aria-label={@title} title={@title} class={["sleep-mark", mark_color(@status), @class]} {@rest}>
      <span aria-hidden="true">z</span><span aria-hidden="true">z</span>
    </span>
    """
  end

  @doc """
  A device's mark in a list: its status dot, or `sleep_mark/1` for a
  sleeping device. A dot keeps the mark's 12px, so identifiers after it line
  up whichever a row shows.
  """
  attr(:status, :string, required: true, doc: "from `list_status/2`")
  attr(:connection, :any, required: true, doc: "the device's latest `DeviceConnection`, or nil")
  attr(:class, :any, default: nil)

  def status_mark(%{status: status} = assigns) when status in ["asleep", "overdue"] do
    ~H"""
    <.sleep_mark status={@status} title={mark_title(@status, @connection)} class={@class} />
    """
  end

  def status_mark(assigns) do
    ~H"""
    <.status_dot
      class={["mr-1.25 size-1.75", if(@status == "online", do: "bg-status-online", else: "bg-status-offline"), @class]}
      title={mark_title(@status, @connection)}
    />
    """
  end

  @doc """
  What the device page header and the devices list's side panel say about a
  sleeping device, in place of its connection: "Asleep back in 5 minutes", or
  "Overdue was due back 20 minutes ago", with when it is due in a tooltip. A
  device still connected while it goes to sleep shows "going to sleep" after
  its connection instead. Renders nothing for a connection that did not end in
  sleep.
  """
  attr(:id, :string, required: true)
  attr(:connection, :any, required: true, doc: "the device's latest `DeviceConnection`, or nil")
  attr(:time_zone, :string, default: nil)

  attr(:compact, :boolean,
    default: false,
    doc: "the side panel's smaller text, spaced by the line it sits in rather than padding of its own"
  )

  attr(:now, DateTime,
    default: nil,
    doc: "the time to judge it at; pass a ticking assign so the summary follows the clock"
  )

  def sleep_summary(assigns) do
    now = assigns.now || DateTime.utc_now()
    assigns = assign(assigns, now: now, state: DeviceConnection.sleep_state(assigns.connection, now))

    ~H"""
    <span
      :if={@state == :going_to_sleep}
      id={@id}
      class={["shrink-0 text-content-muted", if(@compact, do: "text-ui/4", else: "pl-1.25 text-sm/4.5")]}
    >
      going to sleep
    </span>
    <.tooltip :if={@state in [:asleep, :overdue]} id={@id} placement="bottom">
      <span class={["flex shrink-0 items-baseline gap-1.25", if(@compact, do: "text-ui/4", else: "pl-0.5 text-sm/4.5")]}>
        <span class={["font-medium", if(@state == :overdue, do: "text-warning-content", else: "text-success-content")]}>
          {if @state == :overdue, do: "Overdue", else: "Asleep"}
        </span>
        <span :if={due(@state, @connection, @now)} class="text-content-muted">{due(@state, @connection, @now)}</span>
      </span>
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
  A sentence for a `title` or tooltip about a sleeping device, such as
  "Asleep, back in 5 minutes", or nil when it is not asleep.
  """
  @spec describe(DeviceConnection.t() | nil) :: String.t() | nil
  def describe(connection) do
    now = DateTime.utc_now()

    case DeviceConnection.sleep_state(connection, now) do
      nil -> nil
      :going_to_sleep -> "Going to sleep"
      state -> sentence(state, connection, now)
    end
  end

  defp mark_color("overdue"), do: "text-status-overdue"
  defp mark_color(_asleep), do: "text-status-asleep"

  defp mark_title("online", _connection), do: "Online"

  defp mark_title(status, connection) when status in ["asleep", "overdue"] do
    describe(connection) || "Offline"
  end

  defp mark_title(_status, _connection), do: "Offline"

  defp sentence(:asleep, %{expected_wake_at: nil}, _now), do: "Asleep"

  defp sentence(state, connection, now) do
    label = if state == :overdue, do: "Overdue", else: "Asleep"
    "#{label}, #{due(state, connection, now)}"
  end

  # When it's due, after "Asleep" or "Overdue": "back in 5 minutes", "due
  # back now", "was due back 20 minutes ago", or nil when it gave no time.
  defp due(_state, %{expected_wake_at: nil}, _now), do: nil

  defp due(:asleep, %{expected_wake_at: at}, now) do
    if DateTime.after?(at, now), do: "back #{RelativeTime.from_now(at, now)}", else: "due back now"
  end

  defp due(:overdue, %{expected_wake_at: at}, now), do: "was due back #{RelativeTime.from_now(at, now)}"

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

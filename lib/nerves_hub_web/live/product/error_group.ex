defmodule NervesHubWeb.Live.Product.ErrorGroup do
  @moduledoc """
  One error, across the whole fleet.

  The header and the Events, First seen and Last seen figures are the
  PostgreSQL row, which is why they are still here after the occurrences have
  aged out. Everything else (the chart, the devices, the latest event, the
  split by firmware) is read from the 30 days of reports ClickHouse keeps, so
  it all goes empty together once they are gone.
  """

  use NervesHubWeb, :live_view

  import NervesHubWeb.Components.ErrorReports
  import NervesHubWeb.Components.Fleet, only: [delimited: 1]

  alias NervesHub.AuditLogs.ProductTemplates
  alias NervesHub.Devices
  alias NervesHub.ErrorReports
  alias NervesHub.ErrorReports.ErrorReport
  alias NervesHub.Helpers.RelativeTime
  alias NervesHubWeb.Helpers.Timezone
  alias NervesHubWeb.Mounts.RequireEveryDevice

  on_mount(RequireEveryDevice)

  @periods ~w(24h 7d 30d)
  @top_devices 5
  # The share of events one firmware has to carry before the page says so.
  @tip_share 0.8

  @impl Phoenix.LiveView
  @decorate requires_membership()
  def mount(%{"id" => id}, _session, %{assigns: %{current_scope: scope}} = socket) do
    group = ErrorReports.get_group!(scope.product, id)

    socket
    |> assign(:product, scope.product)
    |> assign(:group, group)
    |> assign(:period, "30d")
    |> assign(:page_title, "#{short_name(group.reason)} · #{scope.product.name} Errors")
    |> sidebar_tab(:errors)
    |> load_reports()
    |> ok()
  end

  @impl Phoenix.LiveView
  @decorate requires_membership()
  def handle_event("select-period", %{"period" => period}, socket) when period in @periods do
    socket
    |> assign(:period, period)
    |> assign_chart()
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("select-period", _params, socket), do: noreply(socket)

  @decorate requires_membership()
  def handle_event("occurrence", %{"index" => index}, socket) do
    case Integer.parse(index) do
      {index, ""} when index >= 0 and index < socket.assigns.retained_count ->
        socket
        |> assign_occurrence(index)
        |> noreply()

      _ ->
        noreply(socket)
    end
  end

  @decorate requires_permission(:"error_group:update")
  def handle_event("resolve", _params, socket), do: act(socket, :resolve)
  @decorate requires_permission(:"error_group:update")
  def handle_event("mute", _params, socket), do: act(socket, :mute)
  @decorate requires_permission(:"error_group:update")
  def handle_event("reopen", _params, socket), do: act(socket, :reopen)

  defp act(%{assigns: %{current_scope: scope, group: group}} = socket, action) do
    case apply_action(action, group, scope.user) do
      {:ok, updated} ->
        _ = audit(action, scope, updated)

        socket
        |> assign(:group, ErrorReports.get_group!(scope.product, updated.id))
        |> put_flash(:info, flash_message(action, group))
        |> assign_chart()
        |> noreply()

      {:error, _changeset} ->
        socket
        |> put_flash(:error, "The error could not be updated. Please try again.")
        |> noreply()
    end
  end

  defp apply_action(:resolve, group, user), do: ErrorReports.resolve(group, user)
  defp apply_action(:mute, group, user), do: ErrorReports.mute(group, user)
  defp apply_action(:reopen, group, _user), do: ErrorReports.reopen(group)

  defp audit(:resolve, scope, group), do: ProductTemplates.audit_error_group_resolved(scope.user, scope.product, group)

  defp audit(:mute, scope, group), do: ProductTemplates.audit_error_group_muted(scope.user, scope.product, group)

  defp audit(:reopen, scope, group), do: ProductTemplates.audit_error_group_reopened(scope.user, scope.product, group)

  defp flash_message(:resolve, _group), do: "Resolved. It reopens as Regressed if it happens again."
  defp flash_message(:mute, _group), do: "Muted. It keeps counting and won’t reopen."
  defp flash_message(:reopen, %{status: :muted}), do: "Unmuted. The error is back in Unresolved."
  defp flash_message(:reopen, _group), do: "Reopened. The error is back in Unresolved."

  defp load_reports(%{assigns: %{group: group, product: product}} = socket) do
    by_firmware = ErrorReports.occurrences_by_firmware(group)

    uuids =
      [group.first_seen_firmware_uuid, group.last_seen_firmware_uuid | Enum.map(by_firmware, & &1.firmware_uuid)]

    firmware = ErrorReports.firmware_by_uuid(product, uuids)
    last_seen = firmware_label(group.last_seen_firmware_uuid, firmware)

    socket
    |> assign(:retained_count, ErrorReports.retained_count(group))
    |> assign(:device_count, ErrorReports.affected_device_count(group))
    |> assign(:top_devices, ErrorReports.affected_devices(group, order: :count, limit: @top_devices))
    |> assign(:by_firmware, by_firmware)
    |> assign(:firmware, firmware)
    |> assign(:release, last_seen && !last_seen.deleted? && ErrorReports.first_release(product, last_seen.text))
    |> assign_occurrence(0)
    |> assign_chart()
  end

  defp assign_occurrence(%{assigns: %{group: group}} = socket, index) do
    occurrence = group |> ErrorReports.occurrences(offset: index, limit: 1) |> List.first()

    socket
    |> assign(:occurrence, occurrence)
    |> assign(:occurrence_device, occurrence && occurrence_device(occurrence, socket.assigns))
    |> assign(:occurrence_index, index)
  end

  # Most often one of the devices hit most, already loaded. A device deleted
  # since it reported is `nil`, and the event says so.
  defp occurrence_device(occurrence, assigns) do
    case Enum.find(assigns.top_devices, &(&1.device.id == occurrence.device_id)) do
      %{device: device} ->
        device

      nil ->
        case Devices.get_device_by(id: occurrence.device_id, product_id: assigns.product.id) do
          {:ok, device} -> device
          {:error, :not_found} -> nil
        end
    end
  end

  defp assign_chart(%{assigns: assigns} = socket) do
    time_zone = Timezone.resolve(assigns[:time_zone])
    buckets = buckets(assigns.group, assigns.period, time_zone)
    {window_start, _} = List.first(buckets).span
    {_, window_end} = List.last(buckets).span

    bars =
      Enum.map(buckets, fn bucket ->
        %{count: bucket.count, hot?: hot_bucket?(assigns.group, bucket.span), label: bucket.label}
      end)

    markers =
      [
        {:resolved, assigns.group.resolved_at},
        {:release, assigns.release && assigns.release.at}
      ]
      |> Enum.filter(fn {_kind, at} -> at && within?(at, window_start, window_end) end)
      |> Enum.map(fn {kind, at} ->
        %{kind: kind, x: DateTime.diff(at, window_start) / DateTime.diff(window_end, window_start)}
      end)

    socket
    |> assign(:bars, bars)
    |> assign(:markers, markers)
    |> assign(:axis, axis(buckets, assigns.period))
  end

  defp buckets(group, "24h", time_zone) do
    now = DateTime.utc_now()

    group
    |> ErrorReports.occurrences_by_hour(DateTime.add(now, -23, :hour), now)
    |> Enum.map(fn %{hour: hour, count: count} ->
      local = DateTime.shift_zone!(hour, time_zone)

      %{
        count: count,
        span: {hour, DateTime.add(hour, 1, :hour)},
        label: Calendar.strftime(local, "%b %-d %H:00"),
        local: local
      }
    end)
  end

  defp buckets(group, period, time_zone) do
    days = if period == "7d", do: 7, else: 30
    today = time_zone |> DateTime.now!() |> DateTime.to_date()
    from = Date.add(today, -(days - 1))

    group
    |> ErrorReports.occurrences_by_date(from, today, time_zone)
    |> Enum.map(fn %{date: date, count: count} ->
      start = start_of_day(date, time_zone)

      %{
        count: count,
        span: {start, start_of_day(Date.add(date, 1), time_zone)},
        label: Calendar.strftime(date, "%b %-d"),
        local: date
      }
    end)
  end

  defp start_of_day(date, time_zone) do
    case DateTime.new(date, ~T[00:00:00], time_zone) do
      {:ok, at} -> at
      {:ambiguous, first, _second} -> first
      {:gap, _before, after_gap} -> after_gap
    end
    |> DateTime.shift_zone!("Etc/UTC")
  end

  # Red is the stretch the error is open for: since it was last resolved, or
  # all of it if it never was. A resolved or muted error has no open stretch.
  defp hot_bucket?(%{status: :unresolved, resolved_at: nil}, _span), do: true

  defp hot_bucket?(%{status: :unresolved, resolved_at: resolved_at}, {_start, finish}),
    do: DateTime.after?(finish, resolved_at)

  defp hot_bucket?(_group, _span), do: false

  defp within?(at, from, to), do: not DateTime.before?(at, from) and DateTime.before?(at, to)

  # Four labels spread under the bars, the last one now.
  defp axis(buckets, period) do
    count = length(buckets)

    [0, div(count, 3), div(count * 2, 3)]
    |> Enum.map(&Enum.at(buckets, &1).local)
    |> Enum.map(&axis_label(&1, period))
    |> Kernel.++([if(period == "24h", do: "Now", else: "Today")])
  end

  defp axis_label(local, "24h"), do: Calendar.strftime(local, "%H:00")
  defp axis_label(date, _period), do: Calendar.strftime(date, "%b %-d")

  @doc "The chart's periods, with their labels."
  def periods(), do: [{"24 h", "24h"}, {"7 d", "7d"}, {"30 d", "30d"}]

  @doc false
  def chart_title("24h"), do: "Events per hour"
  def chart_title(_period), do: "Events per day"

  @doc "The note after the name in the top bar."
  def top_bar_note(group, time_zone) do
    case badge_kind(group) do
      :regressed -> "regressed #{day_label(group.regressed_at, time_zone)}"
      :resolved -> "resolved #{day_label(group.resolved_at, time_zone)}"
      :muted -> "muted #{day_label(group.muted_at, time_zone)}"
      _ -> "first seen #{day_label(group.first_seen_at, time_zone)}"
    end
  end

  @doc "What follows the badge in the header: who did what, and when."
  def header_note(group, firmware, time_zone) do
    case badge_kind(group) do
      :regressed ->
        resolved = if group.resolved_at, do: "Resolved #{day_label(group.resolved_at, time_zone)} · ", else: ""
        "#{resolved}came back#{on_version(group.last_seen_firmware_uuid, firmware, " with")}"

      :resolved ->
        "#{by(group.resolved_by)}on #{day_label(group.resolved_at, time_zone)} · not seen since #{day_label(group.last_seen_at, time_zone)}"

      :muted ->
        "#{by(group.muted_by)}on #{day_label(group.muted_at, time_zone)} · still counting · won’t reopen"

      _ ->
        "First seen #{RelativeTime.from_now(group.first_seen_at)}#{on_version(group.first_seen_firmware_uuid, firmware, " on")}"
    end
  end

  defp by(%{name: name}), do: "by #{name} "
  defp by(_user), do: ""

  defp on_version(uuid, firmware, word) do
    case firmware_label(uuid, firmware) do
      nil -> ""
      label -> "#{word} #{label.text}"
    end
  end

  @doc """
  When one firmware carries most of an error's events, a line that says so,
  and where that firmware went if it was released. `nil` otherwise.
  """
  def firmware_tip([top, _next | _rest] = rows, firmware, release) do
    total = rows |> Enum.map(& &1.count) |> Enum.sum()
    share = top.count / max(total, 1)

    with true <- share >= @tip_share,
         %{deleted?: false, text: version} <- firmware_label(top.firmware_uuid, firmware) do
      "#{floor(share * 100)}% of events come from #{version}." <> release_note(release, version)
    else
      _ -> nil
    end
  end

  def firmware_tip(_rows, _firmware, _release), do: nil

  defp release_note(%{version: version, deployment_group: group}, version),
    do: " #{group} was the first deployment group to get it."

  defp release_note(_release, _version), do: ""

  @doc "The legend under the chart, one line per marker shown."
  def marker_legend(:resolved, group, _release, time_zone),
    do:
      "Resolved#{if group.resolved_by, do: " by #{group.resolved_by.name}"}, #{day_label(group.resolved_at, time_zone)}"

  def marker_legend(:release, _group, release, time_zone),
    do: "#{release.version} released to #{release.deployment_group}, #{day_label(release.at, time_zone)}"

  @doc "An occurrence's frames, decoded for rendering."
  def frames(nil), do: []
  def frames(occurrence), do: ErrorReport.frames(occurrence)

  @doc false
  def truncated?(occurrence), do: ErrorReport.truncated?(occurrence)

  @doc false
  def last_seen_label(at), do: RelativeTime.from_now(at)

  @doc false
  def online?(%{latest_connection: %{status: :connected}}), do: true
  def online?(_device), do: false

  @doc "How wide a firmware's bar is, as a share of the busiest one."
  def bar_width(count, rows) do
    max = rows |> Enum.map(& &1.count) |> Enum.max(fn -> 1 end) |> max(1)
    "#{Float.round(count * 100 / max, 1)}%"
  end
end

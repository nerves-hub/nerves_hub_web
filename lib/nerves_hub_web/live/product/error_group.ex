defmodule NervesHubWeb.Live.Product.ErrorGroup do
  @moduledoc """
  One error, across the whole fleet.

  Everything on this page except the header comes from ClickHouse: the shape
  over time, which devices are hitting it, and the most recent stacktrace. The
  header — what it is, whether anyone has dealt with it — is the PostgreSQL row,
  which is why it is still here to look at after the occurrences have aged out.
  """

  use NervesHubWeb, :live_view

  alias NervesHub.AuditLogs.ProductTemplates
  alias NervesHub.ErrorReports
  alias NervesHub.ErrorReports.ErrorReport

  @periods %{"seven_days" => 7, "fourteen_days" => 14, "four_weeks" => 28}

  @impl Phoenix.LiveView
  def mount(%{"id" => id}, _session, %{assigns: %{current_scope: scope}} = socket) do
    group = ErrorReports.get_group!(scope.product, id)

    socket
    |> assign(:group, group)
    |> assign(:period, "fourteen_days")
    |> assign(:page_title, "#{scope.product.name} Error #{group.id}")
    |> sidebar_tab(:errors)
    |> load_occurrence_data()
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_event("select-period", %{"period" => period}, socket) when is_map_key(@periods, period) do
    socket
    |> assign(:period, period)
    |> assign_chart()
    |> noreply()
  end

  def handle_event("select-period", _params, socket) do
    socket
    |> put_flash(:error, "Invalid period selected")
    |> noreply()
  end

  def handle_event("resolve", _params, socket), do: act(socket, :resolve)
  def handle_event("mute", _params, socket), do: act(socket, :mute)
  def handle_event("reopen", _params, socket), do: act(socket, :reopen)

  defp act(%{assigns: %{current_scope: scope, group: group}} = socket, action) do
    authorized!(:"error_group:update", scope)

    case apply_action(action, group, scope.user) do
      {:ok, updated} ->
        _ = audit(action, scope, updated)

        socket
        |> assign(:group, ErrorReports.get_group!(scope.product, updated.id))
        |> put_flash(:info, flash_message(action))
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

  defp flash_message(:resolve), do: "Error marked as resolved."
  defp flash_message(:mute), do: "Error muted."
  defp flash_message(:reopen), do: "Error reopened."

  defp load_occurrence_data(%{assigns: %{group: group}} = socket) do
    socket
    |> assign(:latest_occurrence, ErrorReports.latest_occurrence(group))
    |> assign(:occurrences, ErrorReports.occurrences(group, limit: 25))
    |> assign(:affected_devices, ErrorReports.affected_devices(group, limit: 25))
    |> assign(:affected_device_count, ErrorReports.affected_device_count(group))
    |> assign_chart()
  end

  defp assign_chart(%{assigns: %{group: group, period: period}} = socket) do
    days = Map.fetch!(@periods, period)
    {time_zone, now} = local_now(socket.assigns[:time_zone])

    to = DateTime.to_date(now)
    from = Date.add(to, -days)

    data =
      group
      |> ErrorReports.occurrences_by_date(from, to, time_zone)
      # The BarChart hook reads `day` and `count`; the context speaks in dates.
      |> Enum.map(&%{day: &1.date, count: &1.count})

    socket
    |> assign(:chart_data, data)
    |> assign(:chart_from, from)
    |> assign(:chart_to, to)
  end

  # Falls back to UTC when the browser's timezone is missing or unrecognised,
  # and hands the same name to ClickHouse that it used to resolve "now".
  defp local_now(time_zone) do
    case time_zone && DateTime.now(time_zone) do
      {:ok, now} -> {time_zone, now}
      _ -> {"Etc/UTC", DateTime.utc_now()}
    end
  end

  @doc "The periods the chart offers."
  def periods(), do: [{"7 days", "seven_days"}, {"14 days", "fourteen_days"}, {"4 weeks", "four_weeks"}]

  @doc "Tailwind classes for a status pill."
  def status_class(:unresolved), do: "bg-base-800 text-orange-400"
  def status_class(:resolved), do: "bg-base-800 text-success"
  def status_class(:muted), do: "bg-base-800 text-base-400"

  @doc "The frames of an occurrence, decoded for rendering."
  def frames(nil), do: []
  def frames(occurrence), do: ErrorReport.frames(occurrence)
end

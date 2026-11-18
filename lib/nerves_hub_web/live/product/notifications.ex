defmodule NervesHubWeb.Live.Product.Notifications do
  use NervesHubWeb, :live_view

  alias NervesHub.Accounts.Scope
  alias NervesHub.Branding
  alias NervesHub.ProductNotifications
  alias NervesHub.ProductNotifications.Copy
  alias NervesHubWeb.Components.ProductSidebar
  alias NervesHubWeb.Helpers.Timezone
  alias NervesHubWeb.Mounts.RequireEveryDevice
  alias Phoenix.Socket.Broadcast

  on_mount(RequireEveryDevice)

  @default_page_size 25
  @page_sizes [@default_page_size, 50, 100]
  @levels ~w(error warning info)

  # How long a notification that just arrived keeps its "New" tag, and one
  # that just happened again keeps its count highlighted.
  @fresh_for to_timeout(second: 10)

  # How many devices an opened card lists, until asked for all of them, and
  # the most it lists then.
  @devices_shown 10
  @devices_shown_at_most 500

  @impl Phoenix.LiveView
  @decorate requires_membership()
  def mount(_params, _session, %{assigns: %{current_scope: scope}} = socket) do
    if connected?(socket) do
      ProductNotifications.subscribe(scope.product.id)
    end

    socket
    |> assign(:page_title, "#{scope.product.name} Notifications")
    |> assign(:platform_name, Branding.friendly_platform_name())
    |> assign(:level, nil)
    |> assign(:page_number, 1)
    |> assign(:page_size, @default_page_size)
    |> assign(:fresh, %{new: MapSet.new(), bumped: MapSet.new(), ref: nil})
    |> assign(:arrived_elsewhere, 0)
    |> assign(:dismissed_by, nil)
    |> assign(:confirming_dismiss_all, false)
    |> assign(:expanded, MapSet.new())
    |> assign(:showing_all, MapSet.new())
    |> sidebar_tab(:notifications)
    |> ok()
  end

  @impl Phoenix.LiveView
  @decorate requires_membership()
  def handle_params(params, _uri, socket) do
    socket
    |> assign(:level, parse_level(params["level"]))
    |> assign(:page_number, parse_positive(params["page_number"], 1))
    |> assign(:page_size, parse_page_size(params["page_size"]))
    |> assign(:arrived_elsewhere, 0)
    |> fetch_notifications()
    |> noreply()
  end

  @impl Phoenix.LiveView
  @decorate requires_permission(:"product:notifications:dismiss")
  def handle_event("dismiss", %{"id" => id}, %{assigns: %{current_scope: scope}} = socket) do
    case ProductNotifications.dismiss(scope, id) do
      {:ok, notification} ->
        socket
        |> put_flash(:info, "Dismissed “#{Copy.card(notification).title}”")
        |> fetch_notifications()
        |> noreply()

      {:error, :not_found} ->
        # Someone else dismissed it first, or it cleared itself.
        socket
        |> fetch_notifications()
        |> noreply()
    end
  end

  @decorate requires_permission(:"product:notifications:dismiss")
  def handle_event("dismiss-card", %{"key" => key}, %{assigns: %{current_scope: scope}} = socket) do
    card = Enum.find(socket.assigns.cards, &(&1.key == key))

    case ProductNotifications.dismiss_card(scope, key) do
      {:ok, count} ->
        socket
        |> put_flash(:info, dismissed_card_flash(card, count))
        |> update(:expanded, &MapSet.delete(&1, key))
        |> fetch_notifications()
        |> noreply()

      {:error, :not_found} ->
        socket
        |> fetch_notifications()
        |> noreply()
    end
  end

  # Opening a card that holds many devices' notifications lists them.
  @decorate requires_membership()
  def handle_event("toggle-card", %{"key" => key}, socket) do
    expanded = socket.assigns.expanded

    expanded =
      cond do
        MapSet.member?(expanded, key) -> MapSet.delete(expanded, key)
        key in rolled_up_keys(socket.assigns.cards) -> MapSet.put(expanded, key)
        true -> expanded
      end

    socket
    |> assign(:expanded, expanded)
    |> fetch_notifications()
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("show-all-devices", %{"key" => key}, socket) do
    socket
    |> update(:showing_all, &if(key in rolled_up_keys(socket.assigns.cards), do: MapSet.put(&1, key), else: &1))
    |> fetch_notifications()
    |> noreply()
  end

  @decorate requires_permission(:"product:notifications:dismiss")
  def handle_event("confirm-dismiss-all", _params, socket) do
    socket
    |> assign(:confirming_dismiss_all, true)
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("cancel-dismiss-all", _params, socket) do
    socket
    |> assign(:confirming_dismiss_all, false)
    |> noreply()
  end

  @decorate requires_permission(:"product:notifications:dismiss")
  def handle_event("dismiss-all", _params, %{assigns: %{current_scope: scope, counts: counts}} = socket) do
    :ok = ProductNotifications.delete_all(scope)

    socket
    |> assign(:confirming_dismiss_all, false)
    |> put_flash(:info, "Dismissed #{ngettext("1 notification", "all %{count} notifications", counts.all)}")
    |> push_patch(to: notifications_path(scope, %{}))
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("hide-dismissed-by", _params, socket) do
    socket
    |> assign(:dismissed_by, nil)
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("set-paginate-opts", %{"page-size" => page_size}, socket) do
    socket
    |> push_patch(to: list_path(socket.assigns, %{"page_size" => page_size, "page_number" => nil}))
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("paginate", %{"page" => page}, socket) do
    socket
    |> push_patch(to: list_path(socket.assigns, %{"page_number" => page}))
    |> noreply()
  end

  @impl Phoenix.LiveView
  # On the first page a notification that arrives slides in, tagged as new,
  # and one that happens again moves to the top with its count lit. On a later
  # page the list stays put under the reader, and a bar says there's something
  # new on the first.
  def handle_info(%Broadcast{event: "created"}, %{assigns: %{page_number: 1}} = socket) do
    before = Map.new(socket.assigns.cards, &{&1.key, {&1.count, &1.occurrences}})
    socket = fetch_notifications(socket)

    {new, bumped} =
      socket.assigns.cards
      |> Enum.reject(&(Map.get(before, &1.key) == {&1.count, &1.occurrences}))
      |> Enum.split_with(&(&1.occurrences == 1 and not Map.has_key?(before, &1.key)))

    socket
    |> mark_fresh(Enum.map(new, & &1.key), Enum.map(bumped, & &1.key))
    |> noreply()
  end

  # Only arrivals the open tab would list count towards the bar, since "Go to
  # newest" keeps the tab.
  def handle_info(%Broadcast{event: "created"}, socket) do
    level = socket.assigns.level || :all
    before = socket.assigns.counts[level]
    counts = ProductNotifications.level_counts(socket.assigns.current_scope.product)

    socket
    |> assign_counts(counts)
    |> update(:arrived_elsewhere, &(&1 + max(counts[level] - before, 0)))
    |> noreply()
  end

  # Something that had raised a notification is no longer the case, or someone
  # dismissed one, so the list changes under the reader with nothing to
  # announce.
  def handle_info(%Broadcast{event: "resolved"}, socket) do
    socket
    |> fetch_notifications()
    |> noreply()
  end

  def handle_info(
        %Broadcast{event: "dismissed", payload: %{dismissed_by: %{id: user_id, name: name}} = payload},
        socket
      ) do
    socket =
      if socket.assigns.current_scope.user.id == user_id do
        socket
      else
        assign(socket, :dismissed_by, %{name: name, count: Map.get(payload, :count)})
      end

    socket
    |> assign(:confirming_dismiss_all, false)
    |> fetch_notifications()
    |> noreply()
  end

  def handle_info({:settle, ref}, %{assigns: %{fresh: %{ref: ref}}} = socket) do
    socket
    |> assign(:fresh, %{new: MapSet.new(), bumped: MapSet.new(), ref: nil})
    |> noreply()
  end

  def handle_info({:settle, _ref}, socket), do: {:noreply, socket}

  defp mark_fresh(socket, [], []), do: socket

  defp mark_fresh(socket, new, bumped) do
    ref = make_ref()
    _ = Process.send_after(self(), {:settle, ref}, @fresh_for)

    assign(socket, :fresh, %{
      new: MapSet.union(socket.assigns.fresh.new, MapSet.new(new)),
      bumped: MapSet.union(socket.assigns.fresh.bumped, MapSet.new(bumped)),
      ref: ref
    })
  end

  defp fetch_notifications(%{assigns: %{current_scope: scope, level: level, page_size: page_size}} = socket) do
    product = scope.product

    {cards, meta, continued_from} =
      ProductNotifications.list_cards(product, socket.assigns.page_number, page_size, level)

    # The opened cards still on the page, and their devices' notifications.
    expanded = MapSet.intersection(socket.assigns.expanded, MapSet.new(rolled_up_keys(cards)))

    members =
      Map.new(expanded, fn key ->
        shown = if MapSet.member?(socket.assigns.showing_all, key), do: @devices_shown_at_most, else: @devices_shown
        {key, ProductNotifications.card_notifications(product, String.to_existing_atom(key), shown)}
      end)

    shown = Enum.map(cards, & &1.latest) ++ Enum.flat_map(members, fn {_key, notifications} -> notifications end)

    socket
    |> assign_counts(ProductNotifications.level_counts(product))
    |> assign(:cards, cards)
    |> assign(:result_meta, meta)
    |> assign(:page_number, meta.current_page)
    |> assign(:expanded, expanded)
    |> assign(:members, members)
    |> assign(:subjects, ProductNotifications.subjects(scope, shown))
    |> assign(:continued_from, continued_from)
  end

  defp rolled_up_keys(cards), do: for(card <- cards, card.count > 1, do: card.key)

  # What an opened card lists: its devices, or its notifications when some
  # device has more than one.
  defp held(%{count: count, devices: count}), do: ngettext("1 device", "%{count} devices", count)
  defp held(%{count: count}), do: ngettext("1 notification", "%{count} notifications", count)

  defp dismissed_card_flash(nil, count), do: "Dismissed #{ngettext("1 notification", "%{count} notifications", count)}"
  defp dismissed_card_flash(card, _count), do: "Dismissed “#{card.title}”"

  # The sidebar counts notifications once, as the page mounts, and this is the
  # page where that count changes in front of the reader.
  defp assign_counts(socket, counts) do
    if connected?(socket) and socket.assigns[:counts] != nil and socket.assigns.counts.all != counts.all do
      send_update(ProductSidebar, id: "product-sidebar", notifications_count: counts.all)
    end

    assign(socket, :counts, counts)
  end

  defp parse_level(level) when level in @levels, do: String.to_existing_atom(level)
  defp parse_level(_level), do: nil

  defp parse_positive(value, default) do
    case Integer.parse(value || "") do
      {number, ""} when number > 0 -> number
      _ -> default
    end
  end

  defp parse_page_size(value) do
    size = parse_positive(value, @default_page_size)
    if size in @page_sizes, do: size, else: @default_page_size
  end

  # More than fits on the smallest page, so the pager has something to do.
  defp paged?(meta), do: meta.total_count > @default_page_size

  # The list's path with `changes` applied to the level, page and page size it
  # is showing. A nil value leaves that one out.
  defp list_path(%{current_scope: scope} = assigns, changes) do
    params =
      %{
        "level" => assigns.level && Atom.to_string(assigns.level),
        "page_number" => assigns.page_number > 1 && Integer.to_string(assigns.page_number),
        "page_size" => assigns.page_size != @default_page_size && Integer.to_string(assigns.page_size)
      }
      |> Map.merge(changes)
      |> Enum.reject(fn {_key, value} -> value in [nil, false] end)
      |> Map.new()

    notifications_path(scope, params)
  end

  defp notifications_path(scope, params) when params == %{}, do: ~p"/org/#{scope.org}/#{scope.product}/notifications"
  defp notifications_path(scope, params), do: ~p"/org/#{scope.org}/#{scope.product}/notifications?#{params}"

  # A level tab starts again at the first page.
  defp level_path(assigns, level), do: list_path(assigns, %{"level" => level, "page_number" => nil})

  defp level_tabs(counts) do
    [
      %{level: nil, param: nil, label: "All", count: counts.all, dot: nil},
      %{level: :error, param: "error", label: "Errors", count: counts.error, dot: "bg-alert"},
      %{level: :warning, param: "warning", label: "Warnings", count: counts.warning, dot: "bg-warning"},
      %{level: :info, param: "info", label: "Info", count: counts.info, dot: "bg-content-faint"}
    ]
  end

  # The cards on the page in groups by when they last happened, the most
  # recent first. The first group says "continued" when the page before ended
  # in the same one.
  defp day_groups(cards, time_zone, continued_from) do
    zone = Timezone.resolve(time_zone)
    today = zone |> DateTime.now!() |> DateTime.to_date()
    continued_bucket = continued_from && bucket(continued_from, zone, today)

    cards
    |> Enum.chunk_by(&bucket(&1.last_occurred_at, zone, today))
    |> Enum.with_index()
    |> Enum.map(fn {[first | _] = group, index} ->
      bucket = bucket(first.last_occurred_at, zone, today)

      %{
        key: bucket_key(bucket),
        label: bucket_label(bucket, today),
        bucket: bucket,
        continued?: index == 0 and bucket == continued_bucket,
        cards: group
      }
    end)
  end

  defp bucket(at, zone, today) do
    date = at |> DateTime.shift_zone!(zone) |> DateTime.to_date()
    week = Date.beginning_of_week(today)

    cond do
      Date.diff(today, date) <= 0 -> :today
      Date.diff(today, date) == 1 -> :yesterday
      Date.compare(date, week) != :lt -> :this_week
      Date.compare(date, Date.add(week, -7)) != :lt -> :last_week
      true -> {:month, date.year, date.month}
    end
  end

  defp bucket_key({:month, year, month}), do: "month-#{year}-#{month}"
  defp bucket_key(bucket), do: Atom.to_string(bucket)

  defp bucket_label(:today, _today), do: "Today"
  defp bucket_label(:yesterday, _today), do: "Yesterday"
  defp bucket_label(:this_week, _today), do: "Earlier this week"
  defp bucket_label(:last_week, _today), do: "Last week"

  defp bucket_label({:month, year, month}, today) do
    name = Calendar.strftime(Date.new!(year, month, 1), "%B")
    if year == today.year, do: name, else: "#{name} #{year}"
  end

  # When a notification last happened, as precisely as its group needs and in
  # the formats other pages use: how long ago today, the time under
  # Yesterday, and the date and time in a group that spans several days.
  defp when_label(at, :today, _time_zone), do: from_now(at)
  defp when_label(at, :yesterday, time_zone), do: to_local_string(at, time_zone, :time, false)
  defp when_label(at, _bucket, time_zone), do: to_local_string(at, time_zone, :short_datetime, false)

  # A device's notification on an opened card says when it last happened as
  # its card would on its own.
  defp device_when_label(at, time_zone) do
    zone = Timezone.resolve(time_zone)
    today = zone |> DateTime.now!() |> DateTime.to_date()
    when_label(at, bucket(at, zone, today), time_zone)
  end

  # A workflow stopped at a step clears its own notification once the step is
  # approved, retried or skipped, so it has no dismiss button.
  defp clears_itself?(card), do: card.kind == :workflow_halted

  defp subject_path(_scope, %{state: state}) when state != :live, do: nil

  defp subject_path(scope, %{kind: :device, ref: identifier}),
    do: ~p"/org/#{scope.org}/#{scope.product}/devices/#{identifier}"

  defp subject_path(scope, %{kind: :deployment_group, ref: name}),
    do: ~p"/org/#{scope.org}/#{scope.product}/deployment_groups/#{name}"

  defp subject_path(scope, _subject), do: ~p"/org/#{scope.org}/settings/integrations"

  defp subject_state_label(:deleted), do: "deleted"
  defp subject_state_label(:moved), do: "moved"
  defp subject_state_label(:removed), do: "removed"

  defp level_label(:error), do: "Error"
  defp level_label(:warning), do: "Warning"
  defp level_label(:info), do: "Info"

  defp empty_level_title(:error), do: "No errors"
  defp empty_level_title(:warning), do: "No warnings"
  defp empty_level_title(:info), do: "No info notifications"

  # What the other tabs hold, for an empty one: "There are 6 warnings and 2
  # info notifications."
  # The verb agrees with the first of them: "There is 1 error and 2 warnings."
  defp elsewhere_sentence(counts, level) do
    [{first, _label} | _] =
      parts =
      Enum.reject(
        [
          error: &ngettext("1 error", "%{count} errors", &1),
          warning: &ngettext("1 warning", "%{count} warnings", &1),
          info: &ngettext("1 info notification", "%{count} info notifications", &1)
        ],
        fn {key, _label} -> key == level or counts[key] == 0 end
      )

    verb = if counts[first] == 1, do: "is", else: "are"

    case Enum.map(parts, fn {key, label} -> label.(counts[key]) end) do
      [one] -> "There #{verb} #{one}."
      many -> "There #{verb} #{Enum.join(Enum.drop(many, -1), ", ")} and #{List.last(many)}."
    end
  end

  attr(:scope, Scope, required: true)
  attr(:subject, :map, required: true)

  # What a notification is about: a link while it's there, and its name and
  # what became of it once it isn't.
  defp subject(assigns) do
    assigns = assign(assigns, :path, subject_path(assigns.scope, assigns.subject))

    ~H"""
    <.link
      :if={@path}
      navigate={@path}
      title={@subject.label}
      class={[
        "max-w-full truncate text-notice-content hover:underline light:text-indigo-600",
        (@subject.kind == :deployment_group && "text-ui") || "font-mono"
      ]}
    >
      {@subject.label}
    </.link>
    <span :if={!@path} title={@subject.label} class={["max-w-full truncate text-content-faint", @subject.kind != :deployment_group && "font-mono"]}>
      {@subject.label} · {subject_state_label(@subject.state)}
    </span>
    """
  end

  attr(:pager, :map, required: true)

  # Sends `set-paginate-opts` and `paginate`, like the shared pager does.
  defp list_footer(assigns) do
    %{current_page: page, page_size: size, total_count: total} = assigns.pager

    assigns =
      assign(assigns,
        first: (page - 1) * size + 1,
        last: min(page * size, total),
        last_page: max(assigns.pager.total_pages, 1),
        page_sizes: @page_sizes
      )

    ~H"""
    <div id="notifications-pager" class="flex items-center justify-between gap-4 pt-2">
      <p class="min-w-0 truncate font-mono text-xs text-content-body">{@first}–{@last} of {@pager.total_count}</p>

      <div class="flex shrink-0 items-center gap-4">
        <form id="notifications-page-size" phx-change="set-paginate-opts" class="flex items-center gap-1.5">
          <label for="notifications-page-size-select" class="text-ui text-content-body max-sm:hidden">Per page</label>
          <span class="grid grid-cols-1">
            <select
              id="notifications-page-size-select"
              name="page-size"
              aria-label="Notifications per page"
              class="col-start-1 row-start-1 h-7 cursor-pointer appearance-none rounded-sm border border-line-control bg-surface-raised bg-none py-0 pr-6 pl-2 font-mono text-xs text-content-strong focus:outline focus:-outline-offset-1 focus:outline-focus-ring"
            >
              <option :for={option <- @page_sizes} value={option} selected={option == @pager.page_size}>{option}</option>
            </select>
            <span class="pointer-events-none col-start-1 row-start-1 mr-1.5 lucide-chevron-down size-3 self-center justify-self-end text-content-muted" aria-hidden="true"></span>
          </span>
        </form>

        <nav aria-label="Pages" class="flex items-center">
          <button
            type="button"
            aria-label="Previous page"
            disabled={@pager.current_page < 2}
            phx-click="paginate"
            phx-value-page={@pager.current_page - 1}
            class="flex size-7 shrink-0 items-center justify-center rounded-l-sm border border-line-control bg-surface-raised text-content-body enabled:cursor-pointer enabled:hover:bg-surface-muted disabled:border-line-default disabled:text-content-faint"
          >
            <span class="lucide-chevron-left size-3.5" aria-hidden="true"></span>
          </button>
          <span aria-current="page" class="flex h-7 items-center border-y border-line-default bg-surface-raised px-2.5 font-mono text-xs whitespace-nowrap text-content-strong">
            {@pager.current_page} / {@last_page}
          </span>
          <button
            type="button"
            aria-label="Next page"
            disabled={@pager.current_page >= @last_page}
            phx-click="paginate"
            phx-value-page={@pager.current_page + 1}
            class="flex size-7 shrink-0 items-center justify-center rounded-r-sm border border-line-control bg-surface-raised text-content-body enabled:cursor-pointer enabled:hover:bg-surface-muted disabled:border-line-default disabled:text-content-faint"
          >
            <span class="lucide-chevron-right size-3.5" aria-hidden="true"></span>
          </button>
        </nav>
      </div>
    </div>
    """
  end

  attr(:count, :integer, required: true)

  defp dismiss_all_dialog(assigns) do
    ~H"""
    <NervesHubWeb.CoreComponents.modal id="dismiss-all-dialog" show on_cancel={JS.push("cancel-dismiss-all")}>
      <div class="flex max-w-lg flex-col gap-4">
        <div class="flex flex-col gap-2">
          <h2 id="dismiss-all-dialog-title" class="text-section-title text-content-strong">
            Dismiss {ngettext("1 notification", "all %{count} notifications", @count)}?
          </h2>
          <p id="dismiss-all-dialog-description" class="text-ui text-content-body">
            This clears them for everyone on this product, on every tab. Any that happen again will come back.
          </p>
        </div>
        <div class="flex justify-end gap-2">
          <.button phx-click={JS.exec("data-cancel", to: "#dismiss-all-dialog")}>Cancel</.button>
          <.button style="contrast" phx-click="dismiss-all">
            Dismiss {ngettext("1", "all %{count}", @count)}
          </.button>
        </div>
      </div>
    </NervesHubWeb.CoreComponents.modal>
    """
  end

  defp toggle_actions_menu() do
    [
      to: "#notifications-actions-menu",
      in: {"ease-out duration-150", "opacity-0", "opacity-100"},
      out: {"ease-out duration-150", "opacity-100", "opacity-0"}
    ]
    |> JS.toggle()
    |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "#notifications-actions-toggle")
  end

  defp hide_actions_menu(js \\ %JS{}) do
    js
    |> JS.hide(to: "#notifications-actions-menu", transition: {"ease-out duration-150", "opacity-100", "opacity-0"})
    |> JS.set_attribute({"aria-expanded", "false"}, to: "#notifications-actions-toggle")
  end
end

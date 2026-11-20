defmodule NervesHubWeb.Live.DeploymentGroups.Index do
  @moduledoc """
  A product's deployment groups, split into Needs you and Running on their own.

  Groups held on a step waiting for approval or stopped on failures come first,
  under Needs you, with the button that moves each on. The rest are shown as
  rows or as cards, by the user's `deployment_group_view` preference. A product
  has a handful of groups, so all of them load at once and the search and
  filters narrow them here rather than in SQL. The page reloads their counts
  every few seconds while it is open.
  """
  use NervesHubWeb, :live_view

  import NervesHubWeb.Components.Fleet, only: [delimited: 1, count_noun: 3]

  alias NervesHub.Accounts
  alias NervesHub.Accounts.User.DisplayPreferences
  alias NervesHub.Firmwares
  alias NervesHub.ManagedDeployments
  alias NervesHubWeb.Components.DeploymentGroups
  alias NervesHubWeb.Mounts.RequireEveryDevice

  on_mount(RequireEveryDevice)

  @refresh_interval to_timeout(second: 5)

  @impl Phoenix.LiveView
  @decorate requires_membership()
  def mount(_params, _session, %{assigns: %{current_scope: scope}} = socket) do
    if connected?(socket), do: schedule_refresh()

    socket
    |> page_title("Deployment Groups - #{scope.product.name}")
    |> sidebar_tab(:deployments)
    |> assign(:filters, %{search: "", platform: nil, firmware: nil})
    |> assign(:confirm, nil)
    |> load_groups()
    |> ok()
  end

  @impl Phoenix.LiveView
  @decorate requires_membership()
  def handle_params(params, _url, socket) do
    filters = %{
      search: String.trim(params["search"] || ""),
      platform: blank_to_nil(params["platform"]),
      firmware: blank_to_nil(params["firmware"])
    }

    socket
    |> assign(:filters, filters)
    |> assign_shown()
    |> noreply()
  end

  @impl Phoenix.LiveView
  @decorate requires_membership()
  def handle_event("filter", params, socket) do
    socket
    |> push_patch(to: self_path(socket, Map.take(params, ["search", "platform", "firmware"])))
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("clear-filters", _params, socket) do
    socket
    |> push_patch(to: self_path(socket, %{}))
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("set-view", %{"view" => view}, %{assigns: %{current_scope: scope}} = socket) do
    case Accounts.update_user_deployment_group_view(scope.user, view) do
      {:ok, user} -> socket |> assign(:current_scope, %{scope | user: user}) |> noreply()
      {:error, _changeset} -> noreply(socket)
    end
  end

  # Approving and skipping send firmware to more devices, so both ask first.
  # Opening the dialog checks the same permission as acting on it.
  @decorate requires_permission(:"deployment_group:update")
  def handle_event("approve", %{"id" => id}, socket) do
    socket
    |> ask(:approve, id, & &1.awaiting_step)
    |> noreply()
  end

  @decorate requires_permission(:"deployment_group:update")
  def handle_event("skip", %{"id" => id}, socket) do
    socket
    |> ask(:skip, id, & &1.failed_step)
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("cancel-confirm", _params, socket) do
    socket
    |> assign(:confirm, nil)
    |> noreply()
  end

  @decorate requires_permission(:"deployment_group:update")
  def handle_event("confirm-approve", %{"id" => id}, socket), do: act(socket, :approve, id)

  @decorate requires_permission(:"deployment_group:update")
  def handle_event("confirm-skip", %{"id" => id}, socket), do: act(socket, :skip, id)

  # Retrying only offers the update again to the devices that failed it, so
  # it runs straight away.
  @decorate requires_permission(:"deployment_group:update")
  def handle_event("retry", %{"id" => id}, socket), do: act(socket, :retry, id)

  @impl Phoenix.LiveView
  def handle_info(:refresh, socket) do
    schedule_refresh()

    socket
    |> load_groups()
    |> assign_shown()
    |> noreply()
  end

  defp schedule_refresh() do
    _ = Process.send_after(self(), :refresh, @refresh_interval)
    :ok
  end

  defp load_groups(%{assigns: %{current_scope: scope}} = socket) do
    entries =
      scope.product
      |> ManagedDeployments.get_deployment_groups_by_product()
      |> DeploymentGroups.load()

    device_counts = ManagedDeployments.get_device_counts_by_product(scope.product)

    socket
    |> assign(:entries, entries)
    |> assign(:grouped_devices, entries |> Enum.map(& &1.counts.total) |> Enum.sum())
    |> assign(:ungrouped_devices, Map.get(device_counts, nil, 0))
    |> assign(
      :platforms,
      entries |> Enum.map(& &1.group.current_release.firmware.platform) |> Enum.uniq() |> Enum.sort()
    )
    |> assign(:versions, versions(entries))
    |> assign(:newest_firmware, entries == [] && Firmwares.get_newest_firmware(scope.product))
  end

  defp versions(entries) do
    entries
    |> Enum.map(& &1.group.current_release.firmware.version)
    |> Enum.uniq()
    |> Enum.sort(&(version_order(&1, &2) != :lt))
  end

  defp version_order(a, b) do
    case {Version.parse(a), Version.parse(b)} do
      {{:ok, a}, {:ok, b}} -> Version.compare(a, b)
      _ -> if a >= b, do: :gt, else: :lt
    end
  end

  defp assign_shown(%{assigns: %{entries: entries, filters: filters}} = socket) do
    shown = Enum.filter(entries, &matches?(&1, filters))
    {needs_you, on_their_own} = Enum.split_with(shown, &DeploymentGroups.needs_you?/1)

    socket
    |> assign(:needs_you, needs_you)
    |> assign(:on_their_own, on_their_own)
    |> assign(:filtering?, filters != %{search: "", platform: nil, firmware: nil})
    |> refresh_confirm()
  end

  defp matches?(%{group: group}, filters) do
    firmware = group.current_release.firmware

    filters.platform in [nil, firmware.platform] and filters.firmware in [nil, firmware.version] and
      search_matches?(group, firmware, filters.search)
  end

  defp search_matches?(_group, _firmware, ""), do: true

  defp search_matches?(group, firmware, search) do
    search = String.downcase(search)

    [group.name, firmware.version | group.conditions.tags || []]
    |> Enum.any?(&String.contains?(String.downcase(&1), search))
  end

  # A dialog left open while the page refreshes keeps showing what it asked
  # about, as the group now stands. It closes if the group moved on.
  defp refresh_confirm(%{assigns: %{confirm: {action, %{group: %{id: id}}}}} = socket) do
    entry = Enum.find(socket.assigns.entries, &(&1.group.id == id))

    case {action, entry} do
      {:approve, %{awaiting_step: %{}}} -> assign(socket, :confirm, {action, entry})
      {:skip, %{failed_step: %{}}} -> assign(socket, :confirm, {action, entry})
      _ -> assign(socket, :confirm, nil)
    end
  end

  defp refresh_confirm(socket), do: socket

  defp ask(socket, action, id, held_step) do
    case find_entry(socket, id) do
      %{} = entry -> if held_step.(entry), do: assign(socket, :confirm, {action, entry}), else: socket
      nil -> socket
    end
  end

  defp act(socket, action, id) do
    case find_entry(socket, id) do
      nil ->
        noreply(socket)

      entry ->
        {level, message} = DeploymentGroups.act(action, entry.group, socket.assigns.current_scope.user)

        socket
        |> assign(:confirm, nil)
        |> put_flash(level, message)
        |> load_groups()
        |> assign_shown()
        |> noreply()
    end
  end

  defp find_entry(socket, id) do
    Enum.find(socket.assigns.entries, &(to_string(&1.group.id) == id))
  end

  defp self_path(%{assigns: %{current_scope: scope}}, params) do
    query = params |> Enum.reject(fn {_key, value} -> value in [nil, ""] end) |> Map.new()

    ~p"/org/#{scope.org}/#{scope.product}/deployment_groups?#{query}"
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp view(user), do: DisplayPreferences.deployment_group_view(user.display_preferences)

  defp group_path(scope, group), do: ~p"/org/#{scope.org}/#{scope.product}/deployment_groups/#{group}"

  # The line under a running group's status badge.
  defp status_detail(%{status: :rolling_out, counts: counts}) do
    [
      counts.updating > 0 && "#{delimited(counts.updating)} updating",
      counts.waiting > 0 && "#{delimited(counts.waiting)} waiting",
      counts.failed > 0 && "#{delimited(counts.failed)} failed",
      counts.penalty_box > 0 && "#{delimited(counts.penalty_box)} in penalty box"
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  defp status_detail(%{status: :up_to_date, counts: %{updates_off: off}}) when off > 0,
    do: "#{delimited(off)} with updates off"

  defp status_detail(%{status: :up_to_date, counts: counts}), do: "All #{delimited(counts.total)} on it"
  defp status_detail(%{status: :paused}), do: "Sends nothing until resumed"
  defp status_detail(%{status: :no_devices}), do: "No devices match yet"
  defp status_detail(_entry), do: nil

  # The counts beside a held group's steps.
  # The phone's card leaves out how many are waiting, so the line fits beside
  # the step it names.
  defp held_counts(entry, waiting? \\ true)

  defp held_counts(%{status: :stopped, counts: counts}, waiting?) do
    [
      "#{delimited(counts.updated)} updated",
      counts.failed + counts.penalty_box > 0 && "#{delimited(counts.failed + counts.penalty_box)} failed",
      waiting? && counts.waiting > 0 && "#{delimited(counts.waiting)} waiting"
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  defp held_counts(%{counts: counts}, _waiting?) do
    [
      counts.failed > 0 && "#{delimited(counts.failed)} failed",
      counts.penalty_box > 0 && "#{delimited(counts.penalty_box)} in penalty box"
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  # Where a held group is in its workflow, for the phone's card.
  defp step_position(%{steps: steps} = entry) do
    step = entry.awaiting_step || entry.failed_step
    "Step #{Enum.find_index(steps, &(&1.id == step.id)) + 1} of #{length(steps)} · #{DeploymentGroups.step_name(step)}"
  end

  # A held group in the list view: why it is held, its steps, and the buttons
  # that move it on.
  attr(:entry, :map, required: true)
  attr(:current_scope, :map, required: true)

  defp held_card(assigns) do
    ~H"""
    <div
      id={"needs-you-#{@entry.group.id}"}
      class={[
        "@container rounded-card border border-l-3 border-line-default bg-surface-raised shadow-card",
        (@entry.status == :stopped && "border-l-alert") || "border-l-waiting"
      ]}
    >
      <div class="flex items-center gap-6 p-5 @max-2xl:flex-col @max-2xl:items-stretch @max-2xl:gap-3 @max-2xl:p-4">
        <div class="flex min-w-0 flex-1 flex-col gap-1.5">
          <div class="flex flex-wrap items-center gap-x-2.5 gap-y-1">
            <.link
              navigate={group_path(@current_scope, @entry.group)}
              class="text-card-title font-semibold text-content-strong hover:underline @max-2xl:flex @max-2xl:basis-full @max-2xl:items-center @max-2xl:justify-between"
            >
              {@entry.group.name}
              <span class="lucide-chevron-right size-4 text-content-faint @2xl:hidden" aria-hidden="true"></span>
            </.link>
            <DeploymentGroups.status_badge status={@entry.status} />
            <span :if={since = DeploymentGroups.held_since(@entry)} class="text-xs text-content-muted">{since}</span>
          </div>

          <p class="text-ui/4.5 text-content-body"><DeploymentGroups.held_sentence entry={@entry} /></p>

          <div class="flex flex-wrap items-center gap-x-3 gap-y-1 pt-1 @max-2xl:hidden">
            <DeploymentGroups.step_trail steps={@entry.steps} />
            <span :if={held_counts(@entry) != ""} class="h-3 w-px bg-line-default" aria-hidden="true"></span>
            <span class="text-xs text-content-muted">{held_counts(@entry)}</span>
          </div>

          <div class="flex flex-col gap-1.5 pt-1 @2xl:hidden">
            <DeploymentGroups.step_bars steps={@entry.steps} step_counts={@entry.step_counts} labels={false} />
            <div class="flex justify-between gap-2 text-xs">
              <span class={["truncate font-medium", (@entry.status == :stopped && "text-alert-content") || "text-waiting-content"]}>
                {step_position(@entry)}
              </span>
              <span class="shrink-0 text-content-muted">{held_counts(@entry, false)}</span>
            </div>
          </div>
        </div>

        <div class="flex shrink-0 items-center gap-2 @max-2xl:*:flex-1 @max-2xl:*:justify-center">
          <.button type="link" size="sm" navigate={group_path(@current_scope, @entry.group)} class="@max-2xl:hidden">Open group</.button>
          <.held_actions entry={@entry} current_scope={@current_scope} />
        </div>
      </div>
    </div>
    """
  end

  # A group as a card, for the grid view: its release, its steps or its
  # rollout, and how far it has got.
  attr(:entry, :map, required: true)
  attr(:current_scope, :map, required: true)
  attr(:time_zone, :string, required: true)

  defp group_card(assigns) do
    ~H"""
    <article
      id={"group-card-#{@entry.group.id}"}
      class={[
        "relative flex flex-col rounded-card border border-line-default bg-surface-raised shadow-card",
        @entry.status == :stopped && "border-l-3 border-l-alert",
        @entry.status == :awaiting_approval && "border-l-3 border-l-waiting"
      ]}
    >
      <header class="flex flex-col gap-1.5 px-5 pt-5 pb-4">
        <div class="flex items-start justify-between gap-3">
          <.link navigate={group_path(@current_scope, @entry.group)} class="truncate text-card-title font-semibold text-content-strong hover:underline">
            {@entry.group.name}
          </.link>
          <DeploymentGroups.status_badge status={@entry.status} class="shrink-0" />
        </div>
        <div class="flex flex-wrap items-center gap-x-2 gap-y-1 font-mono text-xs text-content-muted">
          {@entry.group.current_release.firmware.platform} · {@entry.group.current_release.firmware.architecture} · {count_noun(@entry.counts.total, "device", "devices")}
          <.tag :for={tag <- @entry.group.conditions.tags} mono>{tag}</.tag>
        </div>
      </header>

      <div class="mx-5 h-px bg-line-subtle" aria-hidden="true"></div>

      <dl class="grid grid-cols-[4.5rem_minmax(0,1fr)] gap-x-3 gap-y-4 px-5 py-4">
        <dt class="pt-0.5 text-label text-content-faint uppercase">Release</dt>
        <dd class="flex min-w-0 items-baseline gap-2">
          <span class="shrink-0 font-mono text-ui font-medium text-content-strong">{@entry.group.current_release.firmware.version}</span>
          <span class="truncate text-ui text-content-body">{DeploymentGroups.release_line(@entry.group.current_release)}</span>
          <span class="ml-auto shrink-0 text-xs text-content-muted">{day_label(@entry.group.current_release.inserted_at, @time_zone)}</span>
        </dd>

        <dt class="pt-0.5 text-label text-content-faint uppercase">{(@entry.steps != [] && "Steps") || "Rollout"}</dt>
        <dd :if={@entry.steps != []} class="min-w-0 pt-1">
          <DeploymentGroups.step_bars steps={@entry.steps} step_counts={@entry.step_counts} />
        </dd>
        <dd :if={@entry.steps == []} class="flex min-w-0 flex-col gap-1.5 pt-1">
          <DeploymentGroups.rollout_bar counts={@entry.counts} />
          <span class="text-xs text-content-body">Every matching device</span>
          <span class="-mt-1 font-mono text-2xs text-content-muted">{delimited(@entry.counts.updated)}/{delimited(@entry.counts.total)}</span>
        </dd>
      </dl>

      <footer class="mt-auto flex flex-wrap items-center gap-x-3 gap-y-2 px-5 pb-5">
        <span class="flex items-baseline gap-2">
          <span class="text-figure-sm text-content-strong">{DeploymentGroups.percent_updated(@entry.counts)}%</span>
          <span class="text-xs text-content-muted">on the release</span>
        </span>
        <span class="ml-auto text-xs text-content-muted">
          {if DeploymentGroups.needs_you?(@entry), do: held_counts(@entry), else: status_detail(@entry)}
        </span>
        <.held_actions entry={@entry} current_scope={@current_scope} />
      </footer>
    </article>
    """
  end

  attr(:entry, :map, required: true)
  attr(:current_scope, :map, required: true)

  defp held_actions(assigns) do
    ~H"""
    <%= if authorized?(:"deployment_group:update", @current_scope) do %>
      <.button :if={@entry.status == :awaiting_approval} style="primary" size="sm" phx-click="approve" phx-value-id={@entry.group.id}>
        <span class="lucide-check" aria-hidden="true"></span> Approve and continue
      </.button>
      <.button :if={@entry.status == :stopped} size="sm" phx-click="skip" phx-value-id={@entry.group.id}>Skip step</.button>
      <.button :if={@entry.status == :stopped} style="primary" size="sm" phx-click="retry" phx-value-id={@entry.group.id}>
        <span class="lucide-rotate-ccw" aria-hidden="true"></span> Retry step
      </.button>
    <% end %>
    """
  end
end

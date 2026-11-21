defmodule NervesHubWeb.Components.DeploymentGroupPage.Overview do
  @moduledoc """
  A deployment group's Overview tab: how far its current release has got.

  A callout says why the group is held, if it is (a step waiting for approval,
  a step stopped on failures, or the group paused). Under it, the rollout
  card counts the group's devices by state and walks the release's steps;
  the devices the release didn't reach are listed beside a rail with the
  release itself and how the group matches devices.

  Everything here is drawn from what `NervesHubWeb.Live.DeploymentGroups.Show`
  loads, and its buttons send their events to it.
  """
  use NervesHubWeb, :component
  use Gettext, backend: NervesHubWeb.Gettext

  import NervesHubWeb.Components.Fleet, only: [delimited: 1, count_noun: 3]
  import NervesHubWeb.Components.ProductList, only: [format_megabytes: 1]
  import NervesHubWeb.Helpers.Authorization

  alias NervesHub.Helpers.RelativeTime
  alias NervesHubWeb.Components.DeploymentGroups

  attr(:entry, :map, required: true)
  attr(:unreached, :any, required: true)
  attr(:matched_outside, :integer, required: true)
  attr(:unmatched_inside, :integer, required: true)
  attr(:deltas, :list, required: true)
  attr(:released_by, :string, required: true, doc: "who made the release: a name, or nil when unknown")
  attr(:current_scope, :map, required: true)
  attr(:time_zone, :string, required: true)

  def render(assigns) do
    ~H"""
    <div id="deployment-group-overview" class="@container flex flex-col gap-6 p-4 sm:p-6">
      <.callout entry={@entry} current_scope={@current_scope} />
      <.rollout_card entry={@entry} time_zone={@time_zone} />

      <div class="grid items-start gap-6 @5xl:grid-cols-[minmax(0,1fr)_20rem]">
        <.unreached_card unreached={@unreached} entry={@entry} current_scope={@current_scope} />
        <.rail
          entry={@entry}
          matched_outside={@matched_outside}
          unmatched_inside={@unmatched_inside}
          deltas={@deltas}
          released_by={@released_by}
          current_scope={@current_scope}
          time_zone={@time_zone}
        />
      </div>
    </div>
    """
  end

  attr(:entry, :map, required: true)
  attr(:current_scope, :map, required: true)

  defp callout(%{entry: %{status: :awaiting_approval}} = assigns) do
    assigns = assign(assigns, :step, assigns.entry.awaiting_step)

    ~H"""
    <div id="deployment-group-callout" role="status" class="flex items-center gap-3 rounded-card bg-surface-muted p-3 max-sm:flex-col max-sm:items-stretch">
      <div class="flex min-w-0 flex-1 items-start gap-2.5">
        <span class="mt-px lucide-clock size-4 text-waiting" aria-hidden="true"></span>
        <p class="text-ui/4.5 text-content-body">
          <span class="font-semibold text-content-strong">Step {@step.number}, {DeploymentGroups.step_name(@step)}, is waiting for approval.</span>
          <DeploymentGroups.held_sentence entry={@entry} />
        </p>
      </div>
      <.button :if={authorized?(:"deployment_group:update", @current_scope)} style="primary" size="sm" phx-click="approve" class="shrink-0">
        <span class="lucide-check" aria-hidden="true"></span> Approve and continue
      </.button>
    </div>
    """
  end

  defp callout(%{entry: %{status: :stopped}} = assigns) do
    assigns = assign(assigns, :step, assigns.entry.failed_step)

    ~H"""
    <div id="deployment-group-callout" role="status" class="flex items-center gap-3 rounded-card bg-surface-muted p-3 max-sm:flex-col max-sm:items-stretch">
      <div class="flex min-w-0 flex-1 items-start gap-2.5">
        <span class="mt-px lucide-circle-x size-4 text-alert" aria-hidden="true"></span>
        <p class="text-ui/4.5 text-content-body">
          <span class="font-semibold text-content-strong">Step {@step.number}, {DeploymentGroups.step_name(@step)}, stopped on failures.</span>
          <DeploymentGroups.held_sentence entry={@entry} />
        </p>
      </div>
      <div :if={authorized?(:"deployment_group:update", @current_scope)} class="flex shrink-0 gap-2 max-sm:*:flex-1 max-sm:*:justify-center">
        <.button size="sm" phx-click="skip">Skip step</.button>
        <.button style="primary" size="sm" phx-click="retry">
          <span class="lucide-rotate-ccw" aria-hidden="true"></span> Retry step
        </.button>
      </div>
    </div>
    """
  end

  defp callout(%{entry: %{status: :paused}} = assigns) do
    ~H"""
    <div id="deployment-group-callout" role="status" class="flex items-start gap-2.5 rounded-card bg-surface-muted p-3">
      <span class="mt-px lucide-circle-pause size-4 text-content-muted" aria-hidden="true"></span>
      <p class="text-ui/4.5 text-content-body">
        <span class="font-semibold text-content-strong">This group is paused.</span> It sends nothing, not even to devices that connect, until it’s resumed.
      </p>
    </div>
    """
  end

  defp callout(assigns), do: ~H""

  attr(:entry, :map, required: true)
  attr(:time_zone, :string, required: true)

  defp rollout_card(assigns) do
    assigns = assign(assigns, :release, assigns.entry.group.current_release)

    ~H"""
    <section id="rollout" aria-label="Rollout" class="@container/rollout rounded-card border border-line-default bg-surface-raised shadow-card">
      <div class="flex flex-col gap-3 p-5">
        <div class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
          <p class="flex flex-wrap items-baseline gap-x-2.5">
            <span class="text-figure text-content-strong">{delimited(@entry.counts.updated)}</span>
            <span class="text-ui text-content-body">
              of {count_noun(@entry.counts.total, "device", "devices")} {ngettext("is", "are", @entry.counts.updated)} on
              <span class="font-mono font-medium text-content-strong">{@release.firmware.version}</span>
            </span>
          </p>
          <span class="text-xs text-content-muted">
            Released {to_local_string(@release.inserted_at, @time_zone, :short_datetime, false)} · {from_now(@release.inserted_at)}
          </span>
        </div>
        <DeploymentGroups.rollout_bar counts={@entry.counts} class="h-2" />
        <DeploymentGroups.rollout_legend counts={@entry.counts} workflow={@entry.steps != []} />
      </div>

      <p :if={@entry.steps == []} class="border-t border-line-subtle px-5 py-4 text-ui text-content-muted">
        No steps. Every device that matches gets the release the next time it connects.
      </p>

      <ol :if={@entry.steps != []} aria-label="Steps" class="grid border-t border-line-subtle @3xl/rollout:auto-cols-fr @3xl/rollout:grid-flow-col">
        <.step_cell :for={step <- @entry.steps} step={step} entry={@entry} time_zone={@time_zone} />
      </ol>
    </section>
    """
  end

  attr(:step, :map, required: true)
  attr(:entry, :map, required: true)
  attr(:time_zone, :string, required: true)

  defp step_cell(assigns) do
    assigns =
      assign(assigns,
        state: DeploymentGroups.step_state(assigns.step),
        counts: Map.get(assigns.entry.step_counts, assigns.step.id, %{devices: 0, updated: 0, failed: 0})
      )

    ~H"""
    <li
      id={"step-#{@step.number}"}
      class={[
        "flex flex-col gap-3 border-line-subtle p-5 not-last:border-b @3xl/rollout:not-last:border-r @3xl/rollout:not-last:border-b-0",
        @state == :awaiting && "bg-waiting-soft",
        @state == :failed && "bg-alert-soft/50"
      ]}
    >
      <div class="flex flex-col gap-1">
        <span class={["flex items-center gap-1.5 text-label uppercase", step_label_class(@state)]}>
          <DeploymentGroups.step_icon step={@step} /> Step {@step.number}
        </span>
        <span class="text-ui font-semibold text-content-strong">{DeploymentGroups.step_name(@step)}</span>
        <span class="text-xs text-content-muted">{DeploymentGroups.step_detail(@step)}</span>
      </div>
      <div class="mt-auto flex flex-col gap-2">
        <.step_progress_bar state={@state} counts={@counts} />
        <div class="flex items-baseline justify-between gap-2 text-xs">
          <span :if={@step.type == :approval_required} class={(@state == :awaiting && "text-waiting-content") || "text-content-muted"}>
            {approval_label(@state)}
          </span>
          <span :if={@step.type != :approval_required} class="font-mono text-content-strong">
            {delimited(@counts.updated)}/{delimited(@counts.devices)}<span :if={@counts.failed > 0} class="text-alert-content"> · {delimited(@counts.failed)} failed</span>
          </span>
          <span class="truncate text-content-muted">{step_when(@step, @state, @entry, @time_zone)}</span>
        </div>
      </div>
    </li>
    """
  end

  attr(:state, :atom, required: true)
  attr(:counts, :map, required: true)

  defp step_progress_bar(assigns) do
    ~H"""
    <div class="flex h-1 overflow-hidden rounded-full bg-line-subtle" aria-hidden="true">
      <%= case @state do %>
        <% :completed -> %>
          <span class="size-full bg-success"></span>
        <% :awaiting -> %>
          <span class="size-full bg-waiting"></span>
        <% _ when @counts.devices > 0 -> %>
          <span class="h-full bg-success" style={"width: #{@counts.updated * 100 / @counts.devices}%"}></span>
          <span class="h-full bg-alert" style={"width: #{@counts.failed * 100 / @counts.devices}%"}></span>
        <% _ -> %>
      <% end %>
    </div>
    """
  end

  defp step_label_class(:awaiting), do: "text-waiting-content"
  defp step_label_class(:failed), do: "text-alert-content"
  defp step_label_class(:running), do: "text-notice-content"
  defp step_label_class(_state), do: "text-content-muted"

  defp approval_label(:awaiting), do: "Needs approval"
  defp approval_label(:completed), do: "Approved"
  defp approval_label(:skipped), do: "Skipped"
  defp approval_label(_state), do: "Not yet"

  # When a step finished, or what it waits on. An approval step is done when
  # it is approved, whether or not the next step has started.
  defp step_when(%{type: :approval_required, approved_at: %NaiveDateTime{} = at}, :completed, _entry, time_zone),
    do: "Done #{day_label(at, time_zone)}"

  defp step_when(%{finished_at: %NaiveDateTime{} = at}, :completed, _entry, time_zone),
    do: "Done #{day_label(at, time_zone)}"

  defp step_when(%{skipped_at: %NaiveDateTime{} = at}, :skipped, _entry, time_zone),
    do: "Skipped #{day_label(at, time_zone)}"

  defp step_when(%{finished_at: %NaiveDateTime{} = at}, :failed, _entry, _time_zone), do: "Stopped #{from_now(at)}"

  defp step_when(%{started_at: %NaiveDateTime{} = at}, :awaiting, _entry, _time_zone),
    do: "Waiting #{RelativeTime.elapsed(at)}"

  defp step_when(%{started_at: %NaiveDateTime{} = at}, :running, _entry, _time_zone), do: "Started #{from_now(at)}"

  defp step_when(step, :waiting, entry, _time_zone) do
    case Enum.filter(entry.steps, &(&1.number < step.number)) do
      [] -> "Waiting"
      earlier -> "After #{earlier |> List.last() |> DeploymentGroups.step_name()}"
    end
  end

  defp step_when(_step, _state, _entry, _time_zone), do: nil

  attr(:unreached, :any, required: true)
  attr(:entry, :map, required: true)
  attr(:current_scope, :map, required: true)

  defp unreached_card(assigns) do
    {rows, total} = assigns.unreached
    assigns = assign(assigns, rows: rows, total: total)

    ~H"""
    <section id="unreached" aria-labelledby="unreached-title" class="rounded-card border border-line-default bg-surface-raised shadow-card">
      <div class="flex items-baseline justify-between gap-3 border-b border-line-default px-4 py-3.5">
        <h2 id="unreached-title" class="min-w-0 text-sm/5 font-semibold text-content-strong">Devices this release didn’t reach</h2>
        <.link
          :if={@total > length(@rows)}
          navigate={~p"/org/#{@current_scope.org}/#{@current_scope.product}/devices?deployment_id=#{@entry.group.id}"}
          class="shrink-0 text-xs font-medium text-notice-content hover:underline"
        >
          <span class="sm:hidden">View all</span><span class="max-sm:hidden">View the group’s devices</span>
        </.link>
      </div>

      <p :if={@rows == []} class="px-4 py-6 text-ui text-content-muted">
        None. Every device in the group has {@entry.group.current_release.firmware.version}, is getting it, or is waiting for its step.
      </p>

      <div :if={@rows != []} role="table" aria-labelledby="unreached-title" class="flex flex-col">
        <div role="row" class="flex h-9 items-center gap-4 border-b border-line-default bg-surface-muted px-4 text-label text-content-faint uppercase max-sm:hidden">
          <span role="columnheader" class="w-36 shrink-0">Device</span>
          <span role="columnheader" class="min-w-0 flex-1">What happened</span>
          <span :if={@entry.steps != []} role="columnheader" class="w-40 shrink-0">Step</span>
        </div>
        <div
          :for={row <- @rows}
          id={"unreached-#{row.device.id}"}
          role="row"
          class="flex min-h-13 items-center gap-4 border-b border-line-subtle px-4 py-2 last:border-b-0 max-sm:flex-wrap max-sm:gap-y-1"
        >
          <span role="cell" class="w-36 shrink-0 truncate max-sm:w-full">
            <.link navigate={~p"/org/#{@current_scope.org}/#{@current_scope.product}/devices/#{row.device.identifier}"} class="font-mono text-xs text-notice-content hover:underline">
              {row.device.identifier}
            </.link>
          </span>
          <span role="cell" class="flex min-w-0 flex-1 items-center gap-2 text-ui text-content-body">
            <span class={[unreached_icon(row.state), "size-3.5 shrink-0"]} aria-hidden="true"></span>
            <span class="min-w-0">{unreached_text(row)}</span>
          </span>
          <span :if={@entry.steps != []} role="cell" class="w-40 shrink-0 truncate text-ui text-content-muted max-sm:w-full max-sm:pl-5.5 max-sm:text-xs">
            {(row.step && DeploymentGroups.step_name(row.step)) || "—"}
          </span>
        </div>
      </div>
    </section>
    """
  end

  defp unreached_icon(:penalty_box), do: "lucide-clock--bold text-warning"
  defp unreached_icon(:failed), do: "lucide-circle-x--bold text-alert"
  defp unreached_icon(:updates_off), do: "lucide-circle-minus--bold text-content-faint"

  defp unreached_text(%{state: :penalty_box, device: device}) do
    left = RelativeTime.elapsed(DateTime.utc_now(), device.updates_blocked_until)

    case device.consecutive_failed_updates do
      failures when failures > 0 ->
        "In the penalty box after #{count_noun(failures, "failure", "failures")}, #{left} left"

      _ ->
        "In the penalty box, #{left} left"
    end
  end

  defp unreached_text(%{state: :failed, device: device}),
    do: "Failed to install #{ngettext("once", "%{count} times", device.consecutive_failed_updates)}"

  defp unreached_text(%{state: :updates_off}), do: "Updates are turned off on this device"

  attr(:entry, :map, required: true)
  attr(:matched_outside, :integer, required: true)
  attr(:unmatched_inside, :integer, required: true)
  attr(:deltas, :list, required: true)
  attr(:released_by, :string, required: true, doc: "who made the release: a name, or nil when unknown")
  attr(:current_scope, :map, required: true)
  attr(:time_zone, :string, required: true)

  defp rail(assigns) do
    group = assigns.entry.group
    assigns = assign(assigns, group: group, release: group.current_release)

    ~H"""
    <aside class="flex flex-col gap-6" aria-label="Release and device matching">
      <section :if={is_binary(@group.notes) and String.trim(@group.notes) != ""} id="deployment-group-notes" class="flex flex-col">
        <h2 class="border-b border-line-default pb-2 text-label text-content-muted uppercase">About this group</h2>
        <p class="py-2.5 text-ui whitespace-pre-line text-content-body">{@group.notes}</p>
      </section>

      <section class="flex flex-col">
        <h2 class="border-b border-line-default pb-2 text-label text-content-muted uppercase">Current release</h2>
        <dl class="flex flex-col divide-y divide-line-subtle text-ui">
          <.rail_item :if={line = DeploymentGroups.release_line(@release)} label="Notes">
            <span class="text-content-strong">{line}</span>
          </.rail_item>
          <.rail_item label="Firmware">
            <.link navigate={~p"/org/#{@current_scope.org}/#{@current_scope.product}/firmware/#{@release.firmware}"} class="font-mono text-notice-content hover:underline">
              {@release.firmware.version}
            </.link>
            <%!-- Some firmware (ESP-IDF builds among it) has no size stored. --%>
            <span :if={@release.firmware.size} class="font-mono text-xs text-content-muted"> · {format_megabytes(@release.firmware.size)}</span>
          </.rail_item>
          <.rail_item label="Archive">
            <.link
              :if={@release.archive}
              navigate={~p"/org/#{@current_scope.org}/#{@current_scope.product}/archives/#{@release.archive}"}
              class="font-mono text-notice-content hover:underline"
            >
              {@release.archive.version}
            </.link>
            <span :if={!@release.archive} class="text-content-muted">None</span>
          </.rail_item>
          <.rail_item label="Delta updates">
            <.delta_summary group={@group} deltas={@deltas} current_scope={@current_scope} />
          </.rail_item>
          <.rail_item label="Released by">
            <span class="text-content-strong">{@released_by || "Unknown"}</span>
            <span class="text-content-muted"> · {to_local_string(@release.inserted_at, @time_zone, :short_datetime, false)}</span>
          </.rail_item>
        </dl>
      </section>

      <section class="flex flex-col">
        <h2 class="border-b border-line-default pb-2 text-label text-content-muted uppercase">Device matching</h2>
        <dl class="flex flex-col divide-y divide-line-subtle text-ui">
          <.rail_item label={(@group.conditions.tag_operator == :or && "Has any tag") || "Has every tag"}>
            <span :if={@group.conditions.tags != []} class="flex flex-wrap gap-1">
              <.tag :for={tag <- @group.conditions.tags} mono>{tag}</.tag>
            </span>
            <span :if={@group.conditions.tags == []} class="text-content-strong">No tags needed</span>
          </.rail_item>
          <.rail_item label="Firmware version">
            <span :if={@group.conditions.version not in [nil, ""]} class="font-mono text-content-strong">{@group.conditions.version}</span>
            <span :if={@group.conditions.version in [nil, ""]} class="text-content-strong">Any</span>
          </.rail_item>
        </dl>
        <p :if={@matched_outside > 0} class="pt-3 text-ui text-content-body">
          {count_noun(@matched_outside, "device", "devices")} outside the group {ngettext("matches", "match", @matched_outside)}.
          <button
            :if={authorized?(:"device:set-deployment-group", @current_scope)}
            type="button"
            phx-click="ask-move-in"
            class="cursor-pointer font-medium text-notice-content hover:underline"
          >
            Move {ngettext("it", "them", @matched_outside)} in
          </button>
        </p>
        <p :if={@unmatched_inside > 0} class="pt-3 text-ui text-content-body">
          {count_noun(@unmatched_inside, "device", "devices")} in the group no longer {ngettext("matches", "match", @unmatched_inside)}.
          <button
            :if={authorized?(:"device:set-deployment-group", @current_scope)}
            type="button"
            phx-click="ask-remove-unmatched"
            class="cursor-pointer font-medium text-notice-content hover:underline"
          >
            Remove {ngettext("it", "them", @unmatched_inside)}
          </button>
        </p>
      </section>
    </aside>
    """
  end

  attr(:label, :string, required: true)
  slot(:inner_block, required: true)

  defp rail_item(assigns) do
    ~H"""
    <div class="flex flex-col gap-1 py-3">
      <dt class="text-xs text-content-muted">{@label}</dt>
      <dd class="min-w-0">{render_slot(@inner_block)}</dd>
    </div>
    """
  end

  attr(:group, :map, required: true)
  attr(:deltas, :list, required: true)
  attr(:current_scope, :map, required: true)

  defp delta_summary(%{group: %{delta_updatable: false}} = assigns) do
    ~H"""
    <span class="text-content-strong">Off</span>
    """
  end

  defp delta_summary(%{deltas: []} = assigns) do
    ~H"""
    <span class="text-content-muted">None built yet</span>
    """
  end

  defp delta_summary(assigns) do
    assigns =
      assign(assigns,
        sources: assigns.deltas |> Enum.map(& &1.source.version) |> Enum.uniq(),
        failed: Enum.count(assigns.deltas, &(&1.status in [:failed, :timed_out])),
        building: Enum.count(assigns.deltas, &(&1.status == :processing))
      )

    ~H"""
    <span class="text-content-strong">
      From <.versions versions={@sources} />
    </span>
    <span :if={@building > 0} class="text-content-muted"> · {delimited(@building)} building</span>
    <.link
      :if={@failed > 0}
      navigate={~p"/org/#{@current_scope.org}/#{@current_scope.product}/deployment_groups/#{@group}/releases"}
      class="text-alert-content hover:underline"
    >
      · {delimited(@failed)} failed
    </.link>
    """
  end

  attr(:versions, :list, required: true)

  # "2.4.0", "2.4.0 and 2.3.2", "2.4.0, 2.3.2 and 2 more"
  defp versions(%{versions: versions} = assigns) do
    {shown, rest} = Enum.split(versions, 2)
    assigns = assign(assigns, shown: shown, rest: length(rest))

    ~H"""
    <%= for {version, index} <- Enum.with_index(@shown) do %>
      <span :if={index > 0}>{(index == length(@shown) - 1 && @rest == 0 && " and ") || ", "}</span><span class="font-mono">{version}</span>
    <% end %>
    <span :if={@rest > 0}> and {@rest} more</span>
    """
  end
end

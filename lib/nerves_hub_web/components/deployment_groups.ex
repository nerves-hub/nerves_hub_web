defmodule NervesHubWeb.Components.DeploymentGroups do
  @moduledoc """
  What the deployment groups list and a group's page share: how far a group's
  release has got, the status that sums it up, its workflow steps drawn as a
  trail or as bars, and the dialogs that ask before a step is approved or
  skipped.

  `load/1` turns deployment groups into entries carrying their counts from
  `NervesHub.ManagedDeployments.Rollout`, with two queries for any number of
  groups. `act/4` approves, skips or retries the step a group is held on, for
  both pages.

  The forms on a group's pages (the release dialogs and the Settings cards)
  draw their fields from `field_class/2`, `textarea_class/2`, `select_control/1` and
  `field_error/1`, which follow the design system's form controls.
  """
  use NervesHubWeb, :component
  use Gettext, backend: NervesHubWeb.Gettext

  import NervesHubWeb.Components.Fleet, only: [delimited: 1]

  alias NervesHub.Accounts.User
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep
  alias NervesHub.ManagedDeployments.Rollout
  alias NervesHub.ManagedDeployments.Workflows
  alias NervesHubWeb.Components.Dialog
  alias Phoenix.LiveView.JS

  @typedoc """
  A deployment group with what the pages draw from: how many of its devices
  are in each state, its steps in order with each one's counts, the step it
  is held on, if any, and the status those add up to.
  """
  @type entry() :: %{
          group: DeploymentGroup.t(),
          counts: Rollout.counts(),
          steps: [DeploymentWorkflowStep.t()],
          step_counts: %{pos_integer() => Rollout.step_counts()},
          awaiting_step: DeploymentWorkflowStep.t() | nil,
          failed_step: DeploymentWorkflowStep.t() | nil,
          status: Rollout.status()
        }

  @doc """
  The classes for a one-line field (an input or a select), as the design
  system's form controls draw one: 32px tall with a 4px corner (40px with a
  6px corner and 14px text on a phone), `line-control` sides and top over a
  `line-strong` bottom, an indigo edge with a 3px halo on focus, and red when
  `error?`. A disabled field takes the muted fill. `extra` is appended.

  The vertical padding is zero, as the device filters' fields have it: the
  forms plugin's own padding would push a select's text out of a 32px box.
  """
  @spec field_class(boolean(), String.t() | nil) :: [String.t() | nil]
  def field_class(error?, extra \\ nil), do: control_class("h-8 py-0 text-ui/4 max-sm:h-10", error?, extra)

  @doc """
  The classes for a textarea: a field (`field_class/2`) that grows with its
  rows instead of keeping to 32px.
  """
  @spec textarea_class(boolean(), String.t() | nil) :: [String.t() | nil]
  def textarea_class(error?, extra \\ nil), do: control_class("py-2 text-ui/5", error?, extra)

  defp control_class(size, error?, extra) do
    [
      size,
      "w-full rounded border bg-surface-raised px-2.5 text-content-strong placeholder:text-content-faint focus:ring-3 focus:outline-none max-sm:rounded-md max-sm:text-sm",
      "disabled:cursor-not-allowed disabled:border-line-default disabled:bg-surface-muted disabled:text-content-muted",
      if(error?,
        do: "border-alert focus:border-alert focus:ring-alert/20",
        else: "border-line-control border-b-line-strong focus:border-primary focus:ring-primary/20"
      ),
      extra
    ]
  end

  attr(:id, :string, required: true)
  attr(:name, :string, required: true)
  attr(:error, :boolean, default: false)
  attr(:class, :any, default: nil)
  attr(:rest, :global, include: ~w(disabled form aria-label aria-describedby))
  slot(:inner_block, required: true)

  @doc """
  A select drawn as a field (`field_class/2`) with the design system's 14px
  chevron in `content-faint`, in place of the browser's own arrow.
  """
  def select_control(assigns) do
    ~H"""
    <div class={["grid grid-cols-1", @class]}>
      <select id={@id} name={@name} class={[field_class(@error), "col-start-1 row-start-1 cursor-pointer appearance-none bg-none pr-8"]} {@rest}>
        {render_slot(@inner_block)}
      </select>
      <span class="pointer-events-none col-start-1 row-start-1 mr-2 lucide-chevron-down--bold size-3.5 self-center justify-self-end text-content-faint" aria-hidden="true"></span>
    </div>
    """
  end

  slot(:inner_block, required: true)

  @doc """
  A field's error under it: 12/16 `alert-content` after a 14px icon.
  """
  def field_error(assigns) do
    ~H"""
    <p class="flex items-start gap-1.5 text-xs text-alert-content">
      <span class="mt-px lucide-circle-exclamation-point--bold size-3.5" aria-hidden="true"></span>
      <span>{render_slot(@inner_block)}</span>
    </p>
    """
  end

  @doc """
  Loads the counts for deployment groups whose current release was preloaded
  with its steps, as `ManagedDeployments.get_deployment_groups_by_product/1`
  and `get_by_product_and_name!/3` do.
  """
  @spec load([DeploymentGroup.t()], DateTime.t()) :: [entry()]
  def load(deployment_groups, now \\ DateTime.utc_now()) do
    counts = Rollout.counts(deployment_groups, now)
    step_counts = Rollout.step_counts(deployment_groups, now)

    Enum.map(deployment_groups, fn deployment_group ->
      steps = Enum.sort_by(deployment_group.current_release.steps, & &1.number)
      group_counts = Map.get(counts, deployment_group.id, Rollout.empty_counts())
      awaiting_step = Enum.find(steps, &Workflows.approvable?/1)
      failed_step = Enum.find(steps, &(&1.status == :error))

      %{
        group: deployment_group,
        counts: group_counts,
        steps: steps,
        step_counts: Map.take(step_counts, Enum.map(steps, & &1.id)),
        awaiting_step: awaiting_step,
        failed_step: failed_step,
        status: Rollout.status(deployment_group, group_counts, failed_step, awaiting_step)
      }
    end)
  end

  @doc """
  Whether a group is held until somebody acts: a step waits for approval, or
  stopped on failures.
  """
  @spec needs_you?(entry()) :: boolean()
  def needs_you?(%{status: status}), do: status in [:awaiting_approval, :stopped]

  @doc """
  Approves, skips or retries the step a group is held on, as `user`, and
  nudges the group's orchestrator to carry on. The step is looked up again
  rather than taken from the page, so one somebody else already dealt with is
  refused instead of acted on twice.

  Returns the flash to show.
  """
  @spec act(:approve | :skip | :retry, DeploymentGroup.t(), User.t()) ::
          {:info | :error, String.t()}
  def act(action, deployment_group, user) do
    release_id = deployment_group.current_deployment_release_id

    step =
      case action do
        :approve -> Workflows.awaiting_approval(release_id)
        _ -> Workflows.failed_step(release_id)
      end

    with %DeploymentWorkflowStep{} <- step,
         {:ok, _step} <- run(action, deployment_group, step, user) do
      :ok = ManagedDeployments.broadcast(deployment_group, "deployments/update")
      {:info, done_message(action, step)}
    else
      _ -> {:error, "#{deployment_group.name} has moved on since the page loaded. Nothing was changed."}
    end
  end

  defp run(:approve, deployment_group, step, user), do: Workflows.approve_step(deployment_group, step, user)
  defp run(:skip, deployment_group, step, user), do: Workflows.skip_step(deployment_group, step, user)
  defp run(:retry, deployment_group, step, user), do: Workflows.retry_step(deployment_group, step, user)

  defp done_message(:approve, step), do: "#{step_name(step)} approved. The release carries on with the next step."
  defp done_message(:skip, step), do: "#{step_name(step)} skipped. Its devices are picked up by a later step."
  defp done_message(:retry, step), do: "#{step_name(step)} restarted. Its failed devices are offered the update again."

  @doc "A group's status as a badge."
  attr(:status, :atom, required: true)
  attr(:size, :string, default: "sm")
  attr(:class, :any, default: nil)

  def status_badge(assigns) do
    ~H"""
    <.badge tone={status_tone(@status)} size={@size} dot class={@class}>{status_label(@status)}</.badge>
    """
  end

  @doc "What a group's status is called."
  @spec status_label(Rollout.status()) :: String.t()
  def status_label(:awaiting_approval), do: "Awaiting approval"
  def status_label(:stopped), do: "Stopped"
  def status_label(:paused), do: "Paused"
  def status_label(:up_to_date), do: "Up to date"
  def status_label(:rolling_out), do: "Rolling out"
  def status_label(:no_devices), do: "No devices"

  defp status_tone(:awaiting_approval), do: "waiting"
  defp status_tone(:stopped), do: "alert"
  defp status_tone(:up_to_date), do: "success"
  defp status_tone(:rolling_out), do: "notice"
  defp status_tone(_status), do: "neutral"

  @doc """
  How many of a group's devices are on its release, out of all of them, as a
  whole percentage. A group with no devices is at 0.
  """
  @spec percent_updated(Rollout.counts()) :: non_neg_integer()
  def percent_updated(%{total: 0}), do: 0
  def percent_updated(%{total: total, updated: updated}), do: floor(updated * 100 / total)

  @doc """
  A group's devices as one bar: those on the release, updating, failed, in
  the penalty box and with updates off, in that order, over a track standing
  for those still waiting.
  """
  attr(:counts, :map, required: true)
  attr(:class, :any, default: nil)

  def rollout_bar(assigns) do
    assigns = assign(assigns, :segments, segments(assigns.counts))

    ~H"""
    <div class={["flex h-1.5 gap-0.5 overflow-hidden rounded-full bg-line-subtle", @class]} aria-hidden="true">
      <span :for={{class, share} <- @segments} class={["h-full shrink-0", class]} style={"width: #{share}%"}></span>
    </div>
    """
  end

  @segments [
    updated: "bg-success",
    updating: "bg-primary",
    failed: "bg-alert",
    penalty_box: "bg-warning",
    updates_off: "bg-content-faint"
  ]

  defp segments(%{total: 0}), do: []

  defp segments(counts) do
    for {state, class} <- @segments, counts[state] > 0 do
      {class, Float.round(counts[state] * 100 / counts.total, 2)}
    end
  end

  @doc """
  A key to `rollout_bar/1`, naming each state that has devices in it.
  """
  attr(:counts, :map, required: true)
  attr(:workflow, :boolean, default: false, doc: "whether waiting devices wait for a step")

  def rollout_legend(assigns) do
    assigns =
      assign(assigns, :items, [
        {"bg-success", "On the release", assigns.counts.updated},
        {"bg-primary", "Updating", assigns.counts.updating},
        {"bg-alert", "Failed", assigns.counts.failed},
        {"bg-warning", "Penalty box", assigns.counts.penalty_box},
        {"bg-content-faint", "Updates off", assigns.counts.updates_off},
        {"bg-line-strong", (assigns.workflow && "Waiting for a step") || "Waiting", assigns.counts.waiting}
      ])

    ~H"""
    <ul class="flex flex-wrap gap-x-5 gap-y-1.5 text-xs text-content-muted">
      <li :for={{class, label, count} <- @items} :if={count > 0} class="flex items-center gap-1.5">
        <span class={["size-2 shrink-0 rounded-sm", class]} aria-hidden="true"></span>
        {label} <span class="font-mono text-content-strong">{delimited(count)}</span>
      </li>
    </ul>
    """
  end

  @doc """
  What a step is called: its name, or for one left unnamed, what it is.
  """
  @spec step_name(DeploymentWorkflowStep.t()) :: String.t()
  def step_name(%{name: name} = step) when is_binary(name) do
    case String.trim(name) do
      "" -> step_name(%{step | name: nil})
      name -> name
    end
  end

  def step_name(%{type: :catch_all}), do: "Remaining devices"
  def step_name(%{type: :approval_required}), do: "Approval"
  def step_name(%{number: number}), do: "Step #{number}"

  @doc """
  Where a step stands, as the pages draw it. A step waiting for its approval
  is `:awaiting` rather than `:running`.
  """
  @spec step_state(DeploymentWorkflowStep.t()) :: :completed | :skipped | :failed | :awaiting | :running | :waiting
  def step_state(%{status: :completed}), do: :completed
  def step_state(%{status: :skipped}), do: :skipped
  def step_state(%{status: :error}), do: :failed

  def step_state(%{type: :approval_required, status: :in_progress, approved_at: nil}), do: :awaiting

  # Approved, and waiting for the coordinator to hand on to the next step.
  def step_state(%{type: :approval_required, approved_at: %NaiveDateTime{}}), do: :completed

  def step_state(%{status: :in_progress}), do: :running
  def step_state(_step), do: :waiting

  @doc "A step's icon, coloured by where it stands."
  attr(:step, :map, required: true)
  attr(:class, :any, default: "size-3.5")

  def step_icon(assigns) do
    assigns = assign(assigns, :state, step_state(assigns.step))

    ~H"""
    <span class={[step_icon_class(@state), "shrink-0", @class]} aria-hidden="true"></span>
    """
  end

  defp step_icon_class(:completed), do: "lucide-circle-check--bold text-success"
  defp step_icon_class(:skipped), do: "lucide-circle-minus--bold text-content-faint"
  defp step_icon_class(:failed), do: "lucide-circle-x--bold text-alert"
  defp step_icon_class(:awaiting), do: "lucide-circle-dot--bold text-waiting"
  defp step_icon_class(:running), do: "lucide-circle-dot--bold text-notice"
  defp step_icon_class(:waiting), do: "lucide-circle-dashed--bold text-content-faint"

  @doc "The colour a step's name takes where it is drawn beside its icon."
  @spec step_name_class(DeploymentWorkflowStep.t()) :: String.t()
  def step_name_class(step) do
    case step_state(step) do
      :awaiting -> "font-medium text-waiting-content"
      :failed -> "font-medium text-alert-content"
      :running -> "font-medium text-notice-content"
      :waiting -> "text-content-faint"
      _done -> "text-content-muted"
    end
  end

  @doc """
  A group's steps in a line, each an icon and a name, joined by short rules.
  """
  attr(:steps, :list, required: true)
  attr(:class, :any, default: nil)

  def step_trail(assigns) do
    ~H"""
    <ol class={["flex flex-wrap items-center gap-x-2 gap-y-1", @class]} aria-label="Steps">
      <li :for={{step, index} <- Enum.with_index(@steps)} class="flex items-center gap-2">
        <span :if={index > 0} class="h-px w-4 shrink-0 bg-line-strong" aria-hidden="true"></span>
        <span class="flex items-center gap-1">
          <.step_icon step={step} />
          <span class={["text-xs whitespace-nowrap", step_name_class(step)]}>{step_name(step)}</span>
        </span>
      </li>
    </ol>
    """
  end

  @doc """
  A group's steps side by side, each a bar filled by how far it has got, with
  its name and counts under it unless `labels` is false.
  """
  attr(:steps, :list, required: true)
  attr(:step_counts, :map, required: true)
  attr(:labels, :boolean, default: true)
  attr(:class, :any, default: nil)

  def step_bars(assigns) do
    ~H"""
    <ol class={["flex gap-1", @class]} aria-label="Steps">
      <li :for={step <- @steps} class="flex min-w-0 flex-1 flex-col gap-1.5">
        <.step_bar step={step} counts={Map.get(@step_counts, step.id, %{devices: 0, updated: 0, failed: 0})} />
        <div :if={@labels} class="flex min-w-0 flex-col gap-0.5">
          <span class="line-clamp-2 text-xs text-content-body">{step_name(step)}</span>
          <.step_progress step={step} counts={Map.get(@step_counts, step.id, %{devices: 0, updated: 0, failed: 0})} />
        </div>
      </li>
    </ol>
    """
  end

  attr(:step, :map, required: true)
  attr(:counts, :map, required: true)

  defp step_bar(assigns) do
    assigns = assign(assigns, :state, step_state(assigns.step))

    ~H"""
    <div class="flex h-1 overflow-hidden rounded-full bg-line-subtle" aria-hidden="true">
      <%= case @state do %>
        <% :completed -> %>
          <span class="size-full bg-success"></span>
        <% :awaiting -> %>
          <span class="size-full bg-waiting"></span>
        <% state when state in [:running, :failed] and @counts.devices > 0 -> %>
          <span class="h-full bg-success" style={"width: #{@counts.updated * 100 / @counts.devices}%"}></span>
          <span class="h-full bg-alert" style={"width: #{@counts.failed * 100 / @counts.devices}%"}></span>
        <% _ -> %>
      <% end %>
    </div>
    """
  end

  attr(:step, :map, required: true)
  attr(:counts, :map, required: true)

  defp step_progress(assigns) do
    ~H"""
    <%= cond do %>
      <% step_state(@step) == :awaiting -> %>
        <span class="line-clamp-2 text-2xs text-waiting-content">Needs your approval</span>
      <% @step.type == :approval_required -> %>
        <span class="line-clamp-2 text-2xs text-content-faint">{(step_state(@step) == :completed && "Approved") || "Waits for approval"}</span>
      <% true -> %>
        <%!-- In a narrow column the failed count drops under the progress
             rather than being cut off, as the step's name and the approval
             lines wrap. --%>
        <span class="flex flex-wrap gap-x-1 font-mono text-2xs text-content-muted">
          <span>{delimited(@counts.updated)}/{delimited(@counts.devices)}</span>
          <span :if={@counts.failed > 0} class="whitespace-nowrap text-alert-content">· {delimited(@counts.failed)} failed</span>
        </span>
    <% end %>
    """
  end

  @doc """
  What a step does, in a line: its own description if it has one, otherwise
  what it waits for or which devices it takes.
  """
  @spec step_detail(DeploymentWorkflowStep.t()) :: String.t()
  def step_detail(%{description: description}) when is_binary(description) and description != "", do: description
  def step_detail(%{type: :approval_required}), do: "Waits for someone to approve it"
  def step_detail(%{type: :catch_all}), do: "Every other device in the group"

  def step_detail(%{matching_conditions: conditions}) do
    tags = (conditions && conditions.tags) || []
    limit = conditions && conditions.match_limit

    [
      tags != [] && "Tagged #{Enum.join(tags, ", ")}",
      limit && "up to #{ngettext("1 device", "%{count} devices", limit)}"
    ]
    |> Enum.filter(& &1)
    |> Enum.join(", ")
    |> upcase_first()
  end

  @doc """
  Capitalizes the first letter of a sentence and leaves the rest as written,
  so a tag or an interface name in it keeps its case (`String.capitalize/1`
  would lowercase "LTE" to "lte").
  """
  @spec upcase_first(String.t()) :: String.t()
  def upcase_first(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
  def upcase_first(""), do: ""

  @doc """
  How many of a step's devices may fail before it stops, as written in a
  sentence, or nil if it never stops on failures.
  """
  @spec tolerance_label(DeploymentWorkflowStep.t()) :: String.t() | nil
  def tolerance_label(%{failure_tolerance: %{devices: devices}}) when is_integer(devices), do: "#{devices}"
  def tolerance_label(%{failure_tolerance: %{percent: percent}}) when is_integer(percent), do: "#{percent}%"
  def tolerance_label(_step), do: nil

  @doc """
  The step after `step`, and how many devices it holds.
  """
  @spec next_step(entry(), DeploymentWorkflowStep.t()) :: {DeploymentWorkflowStep.t(), non_neg_integer()} | nil
  def next_step(entry, step) do
    entry.steps
    |> Enum.find(&(&1.number > step.number and &1.type != :approval_required))
    |> case do
      nil -> nil
      next -> {next, entry.step_counts |> Map.get(next.id, %{devices: 0}) |> Map.fetch!(:devices)}
    end
  end

  @doc """
  The sentence that says why a group needs someone: how far its release got
  before the step it is held on.
  """
  attr(:entry, :map, required: true)

  def held_sentence(%{entry: %{status: :awaiting_approval}} = assigns) do
    assigns = assign(assigns, :next, next_step(assigns.entry, assigns.entry.awaiting_step))

    ~H"""
    <span class="font-mono font-medium text-content-strong">{@entry.group.current_release.firmware.version}</span>
    is on {delimited(@entry.counts.updated)} of {delimited(@entry.counts.total)} devices.
    <%= case @next do %>
      <% {next, devices} when devices > 0 -> %>
        Approving {step_name(@entry.awaiting_step)} sends it to {devices_in(next, devices)}.
      <% _ -> %>
        Approving {step_name(@entry.awaiting_step)} lets the release carry on.
    <% end %>
    """
  end

  def held_sentence(%{entry: %{status: :stopped}} = assigns) do
    step = assigns.entry.failed_step

    assigns =
      assign(assigns,
        step: step,
        step_counts: Map.get(assigns.entry.step_counts, step.id, %{devices: 0, failed: 0}),
        tolerance: tolerance_label(step)
      )

    ~H"""
    <span class="font-mono font-medium text-content-strong">{@entry.group.current_release.firmware.version}</span>
    <%= if @step_counts.devices > 0 do %>
      failed to install on {delimited(@step_counts.failed)} of the {delimited(@step_counts.devices)} devices in {step_name(@step)}<span :if={@tolerance}>, over the step’s limit of {@tolerance}</span>.
    <% else %>
      stopped at {step_name(@step)}.
    <% end %>
    <span :if={@entry.counts.waiting > 0}>The other {delimited(@entry.counts.waiting)} are waiting.</span>
    """
  end

  def held_sentence(assigns), do: ~H""

  # The devices a step sends the release to, by name, or as the rest of the
  # group for the catch-all.
  defp devices_in(%{type: :catch_all}, 1), do: "the 1 remaining device"
  defp devices_in(%{type: :catch_all}, devices), do: "the #{delimited(devices)} remaining devices"
  defp devices_in(step, 1), do: "the 1 device in #{step_name(step)}"
  defp devices_in(step, devices), do: "the #{delimited(devices)} devices in #{step_name(step)}"

  @doc """
  How long a group has been held: since its step started waiting for approval,
  or since it stopped.
  """
  @spec held_since(entry()) :: String.t() | nil
  def held_since(%{status: :awaiting_approval, awaiting_step: %{started_at: %NaiveDateTime{} = at}}),
    do: "for #{at |> from_now() |> String.replace(" ago", "")}"

  def held_since(%{status: :stopped, failed_step: %{finished_at: %NaiveDateTime{} = at}}), do: from_now(at)

  def held_since(_entry), do: nil

  @doc """
  The dialog that asks before a step is approved or skipped: both send
  firmware to more devices. `@confirm` is `{:approve | :skip, entry}`.
  """
  attr(:confirm, :any, required: true)

  def confirm_dialog(%{confirm: {:approve, entry}} = assigns) do
    step = entry.awaiting_step
    previous = entry.steps |> Enum.filter(&(&1.number < step.number and &1.type != :approval_required)) |> List.last()

    previous_counts = previous && Map.get(entry.step_counts, previous.id)

    assigns =
      assign(assigns,
        entry: entry,
        step: step,
        next: next_step(entry, step),
        previous: previous_counts && previous_counts.devices > 0 && previous,
        previous_counts: previous_counts
      )

    ~H"""
    <Dialog.confirm id="approve-step" title={"Approve #{step_name(@step)} for #{@entry.group.name}?"} on_cancel={JS.push("cancel-confirm")} wide>
      <p>
        <span class="font-mono text-content-strong">{@entry.group.current_release.firmware.version}</span>
        <%= case @next do %>
          <% {next, devices} when devices > 0 -> %>
            starts going to {devices_in(next, devices)}.
          <% {next, _devices} -> %>
            moves on to {step_name(next)}.
          <% nil -> %>
            carries on to the rest of the group.
        <% end %>
        You can pause the group at any point.
      </p>
      <ul
        :if={@previous || @entry.counts.penalty_box > 0 || @entry.counts.updates_off > 0}
        class="flex flex-col gap-1.5 rounded-card bg-surface-muted px-3 py-2.5 text-ui text-content-body"
      >
        <li :if={@previous} class="flex gap-2">
          <span class="mt-2 size-1 shrink-0 rounded-full bg-content-faint" aria-hidden="true"></span>
          <span>
            {step_name(@previous)} updated <span class="font-mono">{delimited(@previous_counts.updated)}</span>
            of
            <span class="font-mono">{delimited(@previous_counts.devices)}</span><span :if={@previous_counts.failed > 0}>, with {delimited(@previous_counts.failed)} failed</span><span :if={
              tolerance_label(@previous)
            }> (the limit is {tolerance_label(@previous)})</span>
          </span>
        </li>
        <li :if={@entry.counts.penalty_box > 0} class="flex gap-2">
          <span class="mt-2 size-1 shrink-0 rounded-full bg-content-faint" aria-hidden="true"></span>
          {ngettext("1 device stays", "%{count} devices stay", @entry.counts.penalty_box)} in the penalty box until it lifts
        </li>
        <li :if={@entry.counts.updates_off > 0} class="flex gap-2">
          <span class="mt-2 size-1 shrink-0 rounded-full bg-content-faint" aria-hidden="true"></span>
          {ngettext("1 device has", "%{count} devices have", @entry.counts.updates_off)} updates turned off and won’t get it
        </li>
      </ul>
      <:actions>
        <.button style="primary" phx-click="confirm-approve" phx-value-id={@entry.group.id}>
          <span class="lucide-check" aria-hidden="true"></span> Approve and continue
        </.button>
      </:actions>
    </Dialog.confirm>
    """
  end

  def confirm_dialog(%{confirm: {:skip, entry}} = assigns) do
    step = entry.failed_step

    assigns =
      assign(assigns,
        entry: entry,
        step: step,
        next: next_step(entry, step),
        following: Enum.find(entry.steps, &(&1.number > step.number)),
        counts: Map.get(entry.step_counts, step.id, %{devices: 0, failed: 0}),
        tolerance: tolerance_label(step)
      )

    ~H"""
    <Dialog.confirm id="skip-step" title={"Skip #{step_name(@step)} for #{@entry.group.name}?"} on_cancel={JS.push("cancel-confirm")} wide>
      <p>
        <span class="font-mono text-content-strong">{@entry.group.current_release.firmware.version}</span>
        moves on{(@following && " to #{step_name(@following)}") || ""} without {step_name(@step)} finishing.
        <span :if={@counts.failed > 0}>
          It failed on {delimited(@counts.failed)} of the {delimited(@counts.devices)} devices there, and those keep the firmware they have.
        </span>
      </p>
      <ul class="flex flex-col gap-1.5 rounded-card bg-surface-muted px-3 py-2.5 text-ui text-content-body">
        <li :if={@tolerance && @counts.failed > 0} class="flex gap-2">
          <span class="mt-2 size-1 shrink-0 rounded-full bg-content-faint" aria-hidden="true"></span>
          {delimited(@counts.failed)} failed, over the step’s limit of {@tolerance}
        </li>
        <li :if={@next && elem(@next, 1) > 0} class="flex gap-2">
          <span class="mt-2 size-1 shrink-0 rounded-full bg-content-faint" aria-hidden="true"></span> Next, it goes to {devices_in(elem(@next, 0), elem(@next, 1))}
        </li>
        <li class="flex gap-2">
          <span class="mt-2 size-1 shrink-0 rounded-full bg-content-faint" aria-hidden="true"></span> Retry step tries the failed devices again instead
        </li>
      </ul>
      <:actions>
        <.button style="primary" phx-click="confirm-skip" phx-value-id={@entry.group.id}>Skip step</.button>
      </:actions>
    </Dialog.confirm>
    """
  end

  def confirm_dialog(assigns), do: ~H""
end
